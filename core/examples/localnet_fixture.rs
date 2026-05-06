use std::{
    env,
    error::Error,
    io::{self, IsTerminal, Write},
    path::PathBuf,
    thread,
    time::Duration,
};

use solana_sdk::pubkey::Pubkey;

#[path = "localnet_fixture/browser_rpc_proxy.rs"]
mod browser_rpc_proxy;
#[path = "../tests/support/localnet.rs"]
mod localnet;
#[path = "localnet_fixture/manifest.rs"]
mod manifest;

fn main() -> Result<(), Box<dyn Error>> {
    localnet::load_env_files();
    let args = Args::parse()?;

    let clone_rpc_url = args
        .clone_rpc_url
        .unwrap_or_else(localnet::clone_rpc_url_from_env);
    let rpc_port = args
        .rpc_port
        .unwrap_or(localnet::free_validator_rpc_port()?);
    let reserved_validator_ports = localnet::validator_reserved_ports(rpc_port)?;
    let faucet_port = match args.faucet_port {
        Some(port) if reserved_validator_ports.contains(&port) => {
            return Err(
                format!("faucet port {port} conflicts with validator RPC/PubSub ports").into(),
            );
        }
        Some(port) => port,
        None => localnet::free_port_excluding(&reserved_validator_ports)?,
    };
    let ledger_dir = localnet::temp_ledger_dir();

    println!(
        "Cloning Squads from {}",
        localnet::redacted_rpc_url(&clone_rpc_url)
    );
    flush_stdout()?;

    let _validator =
        localnet::LocalValidator::start(&ledger_dir, rpc_port, faucet_port, &clone_rpc_url)?;

    let rpc_url = format!("http://127.0.0.1:{rpc_port}");
    let websocket_url = local_validator_websocket_url(rpc_port)?;
    let rpc = localnet::new_rpc_client(rpc_url.clone());
    localnet::wait_for_validator(&rpc, Duration::from_secs(args.startup_timeout_seconds))?;

    let browser_member = args
        .browser_member
        .or_else(localnet::browser_member_from_env)
        .unwrap_or_else(Pubkey::new_unique);
    let browser_proxy = if args.browser_proxy {
        Some(browser_rpc_proxy::BrowserRpcProxy::start(
            &rpc_url,
            &websocket_url,
            args.browser_proxy_port.unwrap_or(0),
        )?)
    } else {
        None
    };

    println!("Local validator RPC: {rpc_url}");
    println!("Browser member: {browser_member}");
    if let Some(proxy) = &browser_proxy {
        let proxy_url = proxy.proxy_url();
        let proxy_websocket_url = proxy.proxy_websocket_url();
        println!("Browser-safe RPC: {proxy_url}");
        println!("Browser-safe WebSocket: {proxy_websocket_url}");
        println!(
            "Trust simulator CA once: xcrun simctl keychain booted add-root-cert {}",
            shell_quote(&proxy.cert_path().display().to_string())
        );
        println!(
            "Open simulator network endpoint settings: ruby scripts/open-rpc-url.rb {}",
            shell_quote(&proxy_url)
        );
    } else {
        println!("Browser-safe RPC: disabled");
        println!("Local validator WebSocket: {websocket_url}");
        println!(
            "Open simulator network endpoint settings: ruby scripts/open-rpc-url.rb {}",
            shell_quote(&rpc_url)
        );
    }
    println!();
    flush_stdout()?;

    let mut fixture_manifest = args.manifest_path.as_ref().map(|_| {
        manifest::LocalnetFixtureManifest::new(
            rpc_url.clone(),
            websocket_url.clone(),
            browser_proxy.as_ref().map(|proxy| proxy.proxy_url()),
            browser_proxy
                .as_ref()
                .map(|proxy| proxy.proxy_websocket_url()),
            browser_proxy
                .as_ref()
                .map(|proxy| proxy.cert_path().display().to_string()),
            browser_member.to_string(),
            args.scenario.label().to_string(),
        )
    });

    println!("Fixture scenario: {}", args.scenario.label());
    println!();
    flush_stdout()?;

    for index in 1..=args.squad_count {
        let vault_count = if index == 1 { 2 } else { 1 };
        let config = localnet::FixtureConfig {
            browser_member,
            threshold: 1,
            proposal_count: args.proposal_count,
            vault_count,
            memo: format!("Cosign local fixture squad {index}"),
        };
        let fixture = match args.scenario {
            FixtureScenario::Default => localnet::create_squads_fixture(&rpc, &config)?,
            FixtureScenario::InspectionMatrix => {
                let specs = localnet::inspection_matrix_fixture_proposal_specs();
                localnet::create_squads_fixture_with_specs(&rpc, &config, &specs)?
            }
        };

        if let Some(manifest) = &mut fixture_manifest {
            manifest.push_squad(index, &fixture);
        }

        println!("Squad {index}");
        println!("  multisig: {}", fixture.multisig);
        println!("  creator member: {}", fixture.creator_member);
        println!("  browser member: {}", fixture.browser_member);
        println!(
            "  threshold: {} / {}",
            fixture.threshold, fixture.member_count
        );
        for vault_funding in &fixture.vault_fundings {
            println!(
                "  vault[{}]: {}",
                vault_funding.vault_index, vault_funding.vault
            );
            println!("  vault SOL: {} lamports", vault_funding.sol_lamports);
            print_token_funding("SPL token", &vault_funding.spl_token);
            print_token_funding("Token-2022", &vault_funding.token_2022);
        }
        println!("  proposals:");
        for proposal in &fixture.proposals {
            println!(
                "    proposal {}: {} {}",
                proposal.transaction_index,
                proposal.state.label(),
                proposal.kind.label()
            );
            println!("      proposal account: {}", proposal.proposal);
            println!("      transaction account: {}", proposal.transaction);
        }
        flush_stdout()?;
    }

    if let (Some(path), Some(manifest)) = (&args.manifest_path, fixture_manifest.as_ref()) {
        manifest.write_to(path)?;
        println!();
        println!("Fixture manifest: {}", path.display());
        flush_stdout()?;
    }

    hold_validator(args.hold_mode)?;
    Ok(())
}

fn print_token_funding(label: &str, token: &localnet::FixtureTokenFunding) {
    println!("  {label} program: {}", token.program_id);
    println!("  {label} mint: {}", token.mint);
    println!("  {label} account: {}", token.account);
    println!(
        "  {label} amount: {} base units ({} decimals)",
        token.amount, token.decimals
    );
}

#[derive(Clone, Copy, Debug)]
enum HoldMode {
    Auto,
    DurationSeconds(u64),
    UntilStopped,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum FixtureScenario {
    Default,
    InspectionMatrix,
}

impl FixtureScenario {
    fn parse(value: &str) -> Result<Self, Box<dyn Error>> {
        match value {
            "default" => Ok(Self::Default),
            "inspection-matrix" => Ok(Self::InspectionMatrix),
            unknown => Err(format!("unknown fixture scenario: {unknown}").into()),
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Default => "default",
            Self::InspectionMatrix => "inspection-matrix",
        }
    }
}

#[derive(Debug)]
struct Args {
    clone_rpc_url: Option<String>,
    browser_member: Option<Pubkey>,
    rpc_port: Option<u16>,
    faucet_port: Option<u16>,
    browser_proxy: bool,
    browser_proxy_port: Option<u16>,
    squad_count: u32,
    proposal_count: u64,
    scenario: FixtureScenario,
    manifest_path: Option<PathBuf>,
    hold_mode: HoldMode,
    startup_timeout_seconds: u64,
}

impl Args {
    fn parse() -> Result<Self, Box<dyn Error>> {
        let mut args = env::args().skip(1);
        let mut parsed = Args {
            clone_rpc_url: None,
            browser_member: None,
            rpc_port: None,
            faucet_port: None,
            browser_proxy: true,
            browser_proxy_port: None,
            squad_count: 2,
            proposal_count: 3,
            scenario: FixtureScenario::Default,
            manifest_path: None,
            hold_mode: HoldMode::Auto,
            startup_timeout_seconds: 120,
        };

        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--clone-rpc-url" => parsed.clone_rpc_url = Some(next_value(&mut args, &arg)?),
                "--member" => parsed.browser_member = Some(next_value(&mut args, &arg)?.parse()?),
                "--rpc-port" => parsed.rpc_port = Some(next_value(&mut args, &arg)?.parse()?),
                "--faucet-port" => parsed.faucet_port = Some(next_value(&mut args, &arg)?.parse()?),
                "--browser-proxy-port" => {
                    parsed.browser_proxy_port = Some(next_value(&mut args, &arg)?.parse()?)
                }
                "--no-browser-proxy" => parsed.browser_proxy = false,
                "--squads" => parsed.squad_count = next_value(&mut args, &arg)?.parse()?,
                "--proposals" => parsed.proposal_count = next_value(&mut args, &arg)?.parse()?,
                "--scenario" => {
                    parsed.scenario = FixtureScenario::parse(&next_value(&mut args, &arg)?)?
                }
                "--manifest" => parsed.manifest_path = Some(next_value(&mut args, &arg)?.into()),
                "--duration-seconds" => {
                    if matches!(parsed.hold_mode, HoldMode::UntilStopped) {
                        return Err("--duration-seconds cannot be used with --until-stopped".into());
                    }
                    parsed.hold_mode =
                        HoldMode::DurationSeconds(next_value(&mut args, &arg)?.parse()?)
                }
                "--until-stopped" => {
                    if matches!(parsed.hold_mode, HoldMode::DurationSeconds(_)) {
                        return Err("--until-stopped cannot be used with --duration-seconds".into());
                    }
                    parsed.hold_mode = HoldMode::UntilStopped;
                }
                "--startup-timeout-seconds" => {
                    parsed.startup_timeout_seconds = next_value(&mut args, &arg)?.parse()?
                }
                "--help" | "-h" => {
                    print_usage();
                    std::process::exit(0);
                }
                unknown => return Err(format!("unknown argument: {unknown}").into()),
            }
        }

        if parsed.squad_count == 0 {
            return Err("--squads must be greater than 0".into());
        }
        if parsed.proposal_count == 0 {
            return Err("--proposals must be greater than 0".into());
        }

        Ok(parsed)
    }
}

fn next_value(
    args: &mut impl Iterator<Item = String>,
    flag: &str,
) -> Result<String, Box<dyn Error>> {
    args.next()
        .ok_or_else(|| format!("{flag} requires a value").into())
}

fn print_usage() {
    println!(
        "Usage: cargo run --manifest-path core/Cargo.toml --example localnet_fixture -- [options]"
    );
    println!();
    println!("Options:");
    println!("  --member <PUBKEY>          Include this pubkey in every fixture Squad");
    println!("  --squads <COUNT>           Number of 1/2 Squads to create (default: 2)");
    println!("  --proposals <COUNT>        Proposals per Squad (default: 3)");
    println!("  --scenario <NAME>          default or inspection-matrix");
    println!("  --clone-rpc-url <URL>      RPC used to clone deployed Squads accounts");
    println!("  --rpc-port <PORT>          Local validator RPC port");
    println!("  --faucet-port <PORT>       Local validator faucet port");
    println!("  --browser-proxy-port <PORT>");
    println!("  --no-browser-proxy         Do not start the browser-safe HTTPS RPC proxy");
    println!("  --manifest <PATH>          Write a JSON fixture manifest");
    println!("  --duration-seconds <N>     Stop automatically after N seconds");
    println!("  --until-stopped            Keep running until this process is stopped");
    println!("  --startup-timeout-seconds <N>");
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn local_validator_websocket_url(rpc_port: u16) -> Result<String, Box<dyn Error>> {
    let websocket_port = localnet::validator_pubsub_port(rpc_port)?;
    Ok(format!("ws://127.0.0.1:{websocket_port}"))
}

fn flush_stdout() -> Result<(), Box<dyn Error>> {
    io::stdout().flush()?;
    Ok(())
}

fn hold_validator(hold_mode: HoldMode) -> Result<(), Box<dyn Error>> {
    if let HoldMode::DurationSeconds(seconds) = hold_mode {
        println!();
        println!("The validator will stay alive for {seconds} seconds.");
        io::stdout().flush()?;
        thread::sleep(Duration::from_secs(seconds));
        return Ok(());
    }

    if matches!(hold_mode, HoldMode::UntilStopped) {
        println!();
        println!("The validator will stay alive until this process is stopped.");
        io::stdout().flush()?;
        loop {
            thread::sleep(Duration::from_secs(3600));
        }
    }

    if io::stdin().is_terminal() {
        println!();
        println!("The validator will stay alive until you press Enter.");
        io::stdout().flush()?;
        let mut input = String::new();
        io::stdin().read_line(&mut input)?;
        return Ok(());
    }

    let seconds = 600;
    println!();
    println!("No interactive stdin detected; keeping validator alive for {seconds} seconds.");
    io::stdout().flush()?;
    thread::sleep(Duration::from_secs(seconds));
    Ok(())
}
