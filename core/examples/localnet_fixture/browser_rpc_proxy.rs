use std::{
    error::Error,
    fs,
    io::{self, Read, Write},
    net::{IpAddr, Ipv4Addr, SocketAddr, TcpListener, TcpStream},
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread::{self, JoinHandle},
    time::Duration,
};

use rcgen::{
    BasicConstraints, CertificateParams, DistinguishedName, DnType, ExtendedKeyUsagePurpose, IsCa,
    KeyUsagePurpose, SanType,
};
use rustls::{
    Certificate as RustlsCertificate, PrivateKey, ServerConfig, ServerConnection, StreamOwned,
};
use url::Url;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

pub struct BrowserRpcProxy {
    addr: SocketAddr,
    cert_path: PathBuf,
    shutdown: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl BrowserRpcProxy {
    pub fn start(
        target_rpc_url: &str,
        target_websocket_url: &str,
        port: u16,
    ) -> Result<Self, Box<dyn Error>> {
        let rpc_target = Url::parse(target_rpc_url)?;
        if rpc_target.scheme() != "http" {
            return Err("browser RPC proxy target must be an HTTP URL".into());
        }
        let websocket_target = Url::parse(target_websocket_url)?;
        if websocket_target.scheme() != "ws" {
            return Err("browser RPC proxy WebSocket target must be a WS URL".into());
        }

        let listener = TcpListener::bind(("127.0.0.1", port))?;
        listener.set_nonblocking(true)?;
        let addr = listener.local_addr()?;
        let certificate = load_or_create_localhost_certificate()?;
        let config = Arc::new(server_config(&certificate)?);
        let shutdown = Arc::new(AtomicBool::new(false));
        let thread_shutdown = Arc::clone(&shutdown);

        let thread = thread::spawn(move || {
            serve(
                listener,
                rpc_target,
                websocket_target,
                config,
                thread_shutdown,
            );
        });

        Ok(Self {
            addr,
            cert_path: certificate.cert_path,
            shutdown,
            thread: Some(thread),
        })
    }

    pub fn proxy_url(&self) -> String {
        format!("https://localhost:{}", self.addr.port())
    }

    pub fn proxy_websocket_url(&self) -> String {
        format!("wss://localhost:{}", self.addr.port())
    }

    pub fn cert_path(&self) -> &Path {
        &self.cert_path
    }
}

impl Drop for BrowserRpcProxy {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::SeqCst);
        let _ = TcpStream::connect(self.addr);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

struct GeneratedCertificate {
    ca_der: Vec<u8>,
    leaf_der: Vec<u8>,
    key_der: Vec<u8>,
    cert_path: PathBuf,
}

struct HttpRequest {
    method: String,
    path: String,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

struct UpstreamResponse {
    status: u16,
    reason: String,
    content_type: String,
    body: Vec<u8>,
}

fn serve(
    listener: TcpListener,
    rpc_target: Url,
    websocket_target: Url,
    config: Arc<ServerConfig>,
    shutdown: Arc<AtomicBool>,
) {
    while !shutdown.load(Ordering::SeqCst) {
        match listener.accept() {
            Ok((tcp, _)) => {
                if shutdown.load(Ordering::SeqCst) {
                    drop(tcp);
                    continue;
                }
                if let Err(error) = tcp.set_nonblocking(false) {
                    eprintln!("HTTPS RPC proxy socket error: {error}");
                    continue;
                }
                let rpc_target = rpc_target.clone();
                let websocket_target = websocket_target.clone();
                let config = Arc::clone(&config);
                thread::spawn(move || {
                    if let Err(error) = handle_client(tcp, rpc_target, websocket_target, config)
                        && !is_expected_client_disconnect(error.as_ref())
                    {
                        eprintln!("HTTPS RPC proxy error: {error}");
                    }
                });
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(25));
            }
            Err(error) => {
                if !shutdown.load(Ordering::SeqCst) {
                    eprintln!("HTTPS RPC proxy accept error: {error}");
                }
            }
        }
    }
}

fn handle_client(
    tcp: TcpStream,
    rpc_target: Url,
    websocket_target: Url,
    config: Arc<ServerConfig>,
) -> Result<(), Box<dyn Error>> {
    let connection = ServerConnection::new(config)?;
    let mut tls = StreamOwned::new(connection, tcp);
    let Some(request) = read_request(&mut tls)? else {
        return Ok(());
    };

    if let Some(origin) = header_value(&request.headers, "origin") {
        eprintln!(
            "HTTPS RPC proxy request: method={} path={} origin={} body_bytes={}",
            request.method,
            request.path,
            origin,
            request.body.len()
        );
    }

    if request.method == "GET" && is_websocket_upgrade(&request) {
        return tunnel_websocket(&websocket_target, &request, tls);
    }

    match request.method.as_str() {
        "OPTIONS" => write_response(
            &mut tls,
            204,
            "No Content",
            cors_headers(&request, None),
            &[],
        )?,
        "POST" => {
            let upstream = forward_rpc(&rpc_target, &request.body)?;
            let headers = cors_headers(&request, Some(&upstream.content_type));
            write_response(
                &mut tls,
                upstream.status,
                &upstream.reason,
                headers,
                &upstream.body,
            )?;
        }
        "GET" => {
            let body = b"Cosign local RPC browser proxy is running. POST Solana JSON-RPC requests to this URL.\n";
            write_response(
                &mut tls,
                200,
                "OK",
                vec![(
                    "Content-Type".to_string(),
                    "text/plain; charset=utf-8".to_string(),
                )],
                body,
            )?;
        }
        _ => write_response(
            &mut tls,
            405,
            "Method Not Allowed",
            cors_headers(&request, None),
            b"Method not allowed\n",
        )?,
    };

    Ok(())
}

fn load_or_create_localhost_certificate() -> Result<GeneratedCertificate, Box<dyn Error>> {
    let cert_dir = local_certificate_dir();
    fs::create_dir_all(&cert_dir)?;
    let ca_pem_path = cert_dir.join("ca.pem");
    let ca_der_path = cert_dir.join("ca.der");
    let leaf_pem_path = cert_dir.join("localhost.pem");
    let leaf_der_path = cert_dir.join("localhost.der");
    let key_pem_path = cert_dir.join("localhost-key.pem");
    let key_der_path = cert_dir.join("localhost-key.der");

    if [&ca_pem_path, &ca_der_path, &leaf_der_path, &key_der_path]
        .iter()
        .all(|path| path.exists())
    {
        return Ok(GeneratedCertificate {
            ca_der: fs::read(&ca_der_path)?,
            leaf_der: fs::read(&leaf_der_path)?,
            key_der: fs::read(&key_der_path)?,
            cert_path: ca_pem_path,
        });
    }

    let mut ca_name = DistinguishedName::new();
    ca_name.push(DnType::CommonName, "Cosign Local RPC Browser Proxy CA");
    let mut ca_params = CertificateParams::default();
    ca_params.distinguished_name = ca_name;
    ca_params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    ca_params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
    let ca_certificate = rcgen::Certificate::from_params(ca_params)?;

    let mut leaf_name = DistinguishedName::new();
    leaf_name.push(DnType::CommonName, "localhost");
    let mut leaf_params = CertificateParams::new(vec!["localhost".to_string()]);
    leaf_params.distinguished_name = leaf_name;
    leaf_params
        .subject_alt_names
        .push(SanType::IpAddress(IpAddr::V4(Ipv4Addr::LOCALHOST)));
    leaf_params.is_ca = IsCa::ExplicitNoCa;
    leaf_params.key_usages = vec![
        KeyUsagePurpose::DigitalSignature,
        KeyUsagePurpose::KeyEncipherment,
    ];
    leaf_params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];
    let leaf_certificate = rcgen::Certificate::from_params(leaf_params)?;

    let ca_pem = ca_certificate.serialize_pem()?;
    let ca_der = ca_certificate.serialize_der()?;
    let leaf_pem = leaf_certificate.serialize_pem_with_signer(&ca_certificate)?;
    let leaf_der = leaf_certificate.serialize_der_with_signer(&ca_certificate)?;
    let key_pem = leaf_certificate.serialize_private_key_pem();
    let key_der = leaf_certificate.serialize_private_key_der();

    fs::write(&ca_pem_path, ca_pem)?;
    fs::write(&ca_der_path, &ca_der)?;
    fs::write(&leaf_pem_path, leaf_pem)?;
    fs::write(&leaf_der_path, &leaf_der)?;
    fs::write(&key_pem_path, key_pem)?;
    fs::write(&key_der_path, &key_der)?;
    #[cfg(unix)]
    {
        fs::set_permissions(&key_pem_path, fs::Permissions::from_mode(0o600))?;
        fs::set_permissions(&key_der_path, fs::Permissions::from_mode(0o600))?;
    }

    Ok(GeneratedCertificate {
        ca_der,
        leaf_der,
        key_der,
        cert_path: ca_pem_path,
    })
}

fn local_certificate_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("core crate has repository parent")
        .join(".cosign-local")
        .join("rpc-proxy")
}

fn server_config(certificate: &GeneratedCertificate) -> Result<ServerConfig, Box<dyn Error>> {
    Ok(ServerConfig::builder()
        .with_safe_defaults()
        .with_no_client_auth()
        .with_single_cert(
            vec![
                RustlsCertificate(certificate.leaf_der.clone()),
                RustlsCertificate(certificate.ca_der.clone()),
            ],
            PrivateKey(certificate.key_der.clone()),
        )?)
}

fn read_request(reader: &mut impl Read) -> Result<Option<HttpRequest>, Box<dyn Error>> {
    let mut headers = Vec::new();
    let mut byte = [0_u8; 1];

    while !headers.ends_with(b"\r\n\r\n") {
        let read = reader.read(&mut byte)?;
        if read == 0 {
            return Ok(None);
        }
        headers.push(byte[0]);
        if headers.len() > 64 * 1024 {
            return Err("HTTP request headers are too large".into());
        }
    }

    let header_text = std::str::from_utf8(&headers)?;
    let mut lines = header_text.split("\r\n");
    let request_line = lines.next().ok_or("missing HTTP request line")?;
    let mut request_parts = request_line.split_whitespace();
    let method = request_parts
        .next()
        .ok_or("missing HTTP method")?
        .to_string();
    let path = request_parts
        .next()
        .ok_or("missing HTTP request path")?
        .to_string();

    let headers = lines
        .filter_map(|line| {
            let (name, value) = line.split_once(':')?;
            Some((name.trim().to_ascii_lowercase(), value.trim().to_string()))
        })
        .collect::<Vec<_>>();

    let content_length = header_value(&headers, "content-length")
        .unwrap_or("0")
        .parse::<usize>()?;
    let mut body = vec![0_u8; content_length];
    reader.read_exact(&mut body)?;

    Ok(Some(HttpRequest {
        method,
        path,
        headers,
        body,
    }))
}

fn tunnel_websocket(
    target: &Url,
    request: &HttpRequest,
    mut client: StreamOwned<ServerConnection, TcpStream>,
) -> Result<(), Box<dyn Error>> {
    let host = target
        .host_str()
        .ok_or("target WebSocket URL is missing a host")?;
    let port = target
        .port_or_known_default()
        .ok_or("target WebSocket URL is missing a port")?;
    let mut upstream = TcpStream::connect((host, port))?;

    {
        client
            .get_mut()
            .set_read_timeout(Some(Duration::from_millis(50)))?;
    }
    upstream.set_read_timeout(Some(Duration::from_millis(50)))?;

    write_websocket_upgrade_request(&mut upstream, request, target)?;
    relay_websocket(client, upstream)
}

fn write_websocket_upgrade_request(
    writer: &mut impl Write,
    request: &HttpRequest,
    target: &Url,
) -> io::Result<()> {
    let path = if request.path.is_empty() {
        "/"
    } else {
        request.path.as_str()
    };
    write!(writer, "{} {path} HTTP/1.1\r\n", request.method)?;
    write!(writer, "Host: {}\r\n", target_authority(target))?;

    for (name, value) in &request.headers {
        if name.eq_ignore_ascii_case("host") {
            continue;
        }
        write!(writer, "{name}: {value}\r\n")?;
    }

    writer.write_all(b"\r\n")?;
    writer.write_all(&request.body)?;
    writer.flush()
}

fn relay_websocket(
    mut client: StreamOwned<ServerConnection, TcpStream>,
    mut upstream: TcpStream,
) -> Result<(), Box<dyn Error>> {
    let mut client_buffer = [0_u8; 16 * 1024];
    let mut upstream_buffer = [0_u8; 16 * 1024];

    loop {
        let mut progressed = false;

        match client.read(&mut client_buffer) {
            Ok(0) => return Ok(()),
            Ok(read) => {
                upstream.write_all(&client_buffer[..read])?;
                upstream.flush()?;
                progressed = true;
            }
            Err(error) if is_temporary_io_error(&error) => {}
            Err(error) => return Err(Box::new(error)),
        }

        match upstream.read(&mut upstream_buffer) {
            Ok(0) => return Ok(()),
            Ok(read) => {
                client.write_all(&upstream_buffer[..read])?;
                client.flush()?;
                progressed = true;
            }
            Err(error) if is_temporary_io_error(&error) => {}
            Err(error) => return Err(Box::new(error)),
        }

        if !progressed {
            thread::sleep(Duration::from_millis(10));
        }
    }
}

fn forward_rpc(target: &Url, body: &[u8]) -> Result<UpstreamResponse, Box<dyn Error>> {
    let host = target
        .host_str()
        .ok_or("target RPC URL is missing a host")?;
    let port = target
        .port_or_known_default()
        .ok_or("target RPC URL is missing a port")?;
    let path = match target.query() {
        Some(query) => format!("{}?{query}", target.path()),
        None if target.path().is_empty() => "/".to_string(),
        None => target.path().to_string(),
    };
    let host_header = match target.port() {
        Some(_) => format!("{host}:{port}"),
        None => host.to_string(),
    };

    let mut upstream = TcpStream::connect((host, port))?;
    let request_head = format!(
        "POST {path} HTTP/1.1\r\nHost: {host_header}\r\nContent-Type: application/json\r\nAccept: application/json\r\nConnection: close\r\nContent-Length: {}\r\n\r\n",
        body.len()
    );
    upstream.write_all(request_head.as_bytes())?;
    upstream.write_all(body)?;
    upstream.flush()?;

    let mut response = Vec::new();
    upstream.read_to_end(&mut response)?;
    parse_response(response)
}

fn parse_response(response: Vec<u8>) -> Result<UpstreamResponse, Box<dyn Error>> {
    let header_end = find_header_end(&response).ok_or("upstream response is missing headers")?;
    let header_text = std::str::from_utf8(&response[..header_end])?;
    let mut lines = header_text.split("\r\n");
    let status_line = lines
        .next()
        .ok_or("upstream response is missing a status line")?;
    let mut status_parts = status_line.splitn(3, ' ');
    let _http_version = status_parts.next();
    let status = status_parts
        .next()
        .ok_or("upstream response is missing a status code")?
        .parse::<u16>()?;
    let reason = status_parts.next().unwrap_or("").to_string();

    let headers = lines
        .filter_map(|line| {
            let (name, value) = line.split_once(':')?;
            Some((name.trim().to_ascii_lowercase(), value.trim().to_string()))
        })
        .collect::<Vec<_>>();
    let content_type = header_value(&headers, "content-type")
        .unwrap_or("application/json; charset=utf-8")
        .to_string();
    let mut body = response[(header_end + 4)..].to_vec();

    if header_value(&headers, "transfer-encoding")
        .map(|value| value.eq_ignore_ascii_case("chunked"))
        .unwrap_or(false)
    {
        body = decode_chunked_body(&body)?;
    }

    Ok(UpstreamResponse {
        status,
        reason,
        content_type,
        body,
    })
}

fn write_response(
    writer: &mut impl Write,
    status: u16,
    reason: &str,
    headers: Vec<(String, String)>,
    body: &[u8],
) -> io::Result<()> {
    write!(writer, "HTTP/1.1 {status} {reason}\r\n")?;
    for (name, value) in headers {
        write!(writer, "{name}: {value}\r\n")?;
    }
    write!(
        writer,
        "Content-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    )?;
    writer.write_all(body)?;
    writer.flush()
}

fn cors_headers(request: &HttpRequest, content_type: Option<&str>) -> Vec<(String, String)> {
    let origin = header_value(&request.headers, "origin").unwrap_or("*");
    let allowed_headers =
        header_value(&request.headers, "access-control-request-headers").unwrap_or("content-type");

    vec![
        (
            "Content-Type".to_string(),
            content_type
                .unwrap_or("application/json; charset=utf-8")
                .to_string(),
        ),
        (
            "Access-Control-Allow-Origin".to_string(),
            origin.to_string(),
        ),
        (
            "Access-Control-Allow-Methods".to_string(),
            "OPTIONS, POST".to_string(),
        ),
        (
            "Access-Control-Allow-Headers".to_string(),
            allowed_headers.to_string(),
        ),
        (
            "Access-Control-Allow-Private-Network".to_string(),
            "true".to_string(),
        ),
        ("Vary".to_string(), "Origin".to_string()),
    ]
}

fn header_value<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers
        .iter()
        .find(|(header_name, _)| header_name.eq_ignore_ascii_case(name))
        .map(|(_, value)| value.as_str())
}

fn is_websocket_upgrade(request: &HttpRequest) -> bool {
    header_value(&request.headers, "upgrade")
        .map(|value| value.eq_ignore_ascii_case("websocket"))
        .unwrap_or(false)
        && header_value(&request.headers, "connection")
            .map(|value| {
                value
                    .split(',')
                    .any(|token| token.trim().eq_ignore_ascii_case("upgrade"))
            })
            .unwrap_or(false)
}

fn target_authority(target: &Url) -> String {
    let host = target.host_str().unwrap_or("localhost");
    match target.port() {
        Some(port) => format!("{host}:{port}"),
        None => host.to_string(),
    }
}

fn is_temporary_io_error(error: &io::Error) -> bool {
    matches!(
        error.kind(),
        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut | io::ErrorKind::Interrupted
    )
}

fn is_expected_client_disconnect(error: &(dyn Error + 'static)) -> bool {
    error
        .downcast_ref::<io::Error>()
        .map(|error| {
            matches!(
                error.kind(),
                io::ErrorKind::UnexpectedEof
                    | io::ErrorKind::ConnectionAborted
                    | io::ErrorKind::ConnectionReset
                    | io::ErrorKind::BrokenPipe
            )
        })
        .unwrap_or_else(|| error.to_string() == "unexpected end of file")
}

fn find_header_end(bytes: &[u8]) -> Option<usize> {
    bytes.windows(4).position(|window| window == b"\r\n\r\n")
}

fn decode_chunked_body(body: &[u8]) -> Result<Vec<u8>, Box<dyn Error>> {
    let mut decoded = Vec::new();
    let mut offset = 0;

    loop {
        let line_end = body[offset..]
            .windows(2)
            .position(|window| window == b"\r\n")
            .map(|position| offset + position)
            .ok_or("chunked response is missing a size line terminator")?;
        let size_text = std::str::from_utf8(&body[offset..line_end])?;
        let size_hex = size_text.split(';').next().unwrap_or("").trim();
        let size = usize::from_str_radix(size_hex, 16)?;
        offset = line_end + 2;

        if size == 0 {
            return Ok(decoded);
        }

        let chunk_end = offset + size;
        if body.len() < chunk_end + 2 || &body[chunk_end..(chunk_end + 2)] != b"\r\n" {
            return Err("chunked response has an invalid chunk body".into());
        }
        decoded.extend_from_slice(&body[offset..chunk_end]);
        offset = chunk_end + 2;
    }
}
