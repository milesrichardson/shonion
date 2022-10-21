use clap::Parser;
use libtor::{HiddenServiceVersion, Tor, TorAddress, TorFlag};

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Host of the destination service to expose to the Tor network
    #[arg(long = "to-host", default_value = "127.0.0.1")]
    proxy_to_host: String,

    /// Port of the destination service to expose to the Tor network
    #[arg(long = "to-port", default_value = "5678")]
    proxy_to_port: u16,

    /// Port to open on the hidden service (blahblah.onion:<tport>)
    #[arg(long = "via-onion-port", default_value = "34567")]
    onion_port: u16,

    /// Local port for the socks proxy to listen on, usable with e.g.:
    /// `curl -x socks5://localhost:19050 ipinfo.io/json`
    #[arg(long = "socks-port", default_value = "19050")]
    socks_port: u16,

    /// Local port for the socks proxy to listen on, usable with e.g.:
    /// `curl -x socks5://localhost:19050 ipinfo.io/json`
    #[arg(long = "config", default_value = "~/.torrc")]
    conf_file: String,
}

// https://2019.www.torproject.org/docs/tor-manual.html.en

fn main() {
    let args = Args::parse();

    Tor::new()
        .flag(TorFlag::ConfigFile(args.conf_file.into()))
        .flag(TorFlag::DataDirectory("/tmp/tor-rust".into()))
        .flag(TorFlag::SocksPort(args.socks_port))
        .flag(TorFlag::HiddenServiceDir("/tmp/tor-rust/hs-dir".into()))
        .flag(TorFlag::HiddenServiceVersion(HiddenServiceVersion::V3))
        .flag(TorFlag::HiddenServicePort(
            TorAddress::Port(args.onion_port),
            Some(TorAddress::AddressPort(
                args.proxy_to_host.into(),
                args.proxy_to_port,
            ))
            .into(),
        ))
        .start()
        .unwrap();
}
