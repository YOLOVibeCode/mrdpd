//! Shared headless IronRDP client for TCC-free E2E (T1-SEC-01/02, T1-GFX-01).
//! Bind 127.0.0.1 only (T1-SEC-04).

use std::io::Write as _;
use std::net::{TcpListener, TcpStream};
use std::time::Duration;

use anyhow::Context as _;
use ironrdp::connector::{self, Credentials as ClientCredentials};
use ironrdp::pdu::gcc::KeyboardType;
use ironrdp::pdu::rdp::capability_sets::MajorPlatformType;
use ironrdp::pdu::rdp::client_info::{CompressionType, PerformanceFlags, TimezoneInfo};
use ironrdp::session::image::DecodedImage;
use ironrdp::session::{ActiveStage, ActiveStageBuilder, ActiveStageOutput};
use ironrdp::pdu::input::fast_path::FastPathInputEvent;
use sspi::network_client::reqwest_network_client::ReqwestNetworkClient;
use tokio_rustls::rustls;

pub fn free_loopback_port() -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").expect("probe bind");
    let port = listener.local_addr().expect("local_addr").port();
    drop(listener);
    port
}

#[allow(dead_code)]
pub fn write_bmp_bgr(path: &std::path::Path, width: u32, height: u32, rgba: &[u8]) -> anyhow::Result<()> {
    let row_stride = (width * 3 + 3) & !3;
    let pixel_bytes = row_stride * height;
    let file_size = 54 + pixel_bytes;
    let mut buf = Vec::with_capacity(file_size as usize);
    buf.extend_from_slice(b"BM");
    buf.extend_from_slice(&file_size.to_le_bytes());
    buf.extend_from_slice(&[0u8; 4]);
    buf.extend_from_slice(&54u32.to_le_bytes());
    buf.extend_from_slice(&40u32.to_le_bytes());
    buf.extend_from_slice(&width.to_le_bytes());
    buf.extend_from_slice(&height.to_le_bytes());
    buf.extend_from_slice(&1u16.to_le_bytes());
    buf.extend_from_slice(&24u16.to_le_bytes());
    buf.extend_from_slice(&[0u8; 24]);
    for y in (0..height).rev() {
        let mut row = vec![0u8; row_stride as usize];
        for x in 0..width {
            let i = ((y * width + x) * 4) as usize;
            let r = rgba[i];
            let g = rgba[i + 1];
            let b = rgba[i + 2];
            let o = (x * 3) as usize;
            row[o] = b;
            row[o + 1] = g;
            row[o + 2] = r;
        }
        buf.extend_from_slice(&row);
    }
    std::fs::write(path, buf).context("write bmp")
}

#[allow(dead_code)]
pub extern "C" fn on_log(_ud: *mut std::ffi::c_void, level: i32, msg: *const std::ffi::c_char) {
    if msg.is_null() {
        return;
    }
    let s = unsafe { std::ffi::CStr::from_ptr(msg) }.to_string_lossy();
    eprintln!("mrdpd-engine[{level}]: {s}");
}

type UpgradedFramed = ironrdp_blocking::Framed<rustls::StreamOwned<rustls::ClientConnection, TcpStream>>;

#[allow(dead_code)]
pub struct ActiveClient {
    pub active_stage: ActiveStage,
    pub framed: UpgradedFramed,
    pub image: DecodedImage,
}

impl ActiveClient {
    #[allow(dead_code)]
    pub fn send_fastpath(&mut self, events: &[FastPathInputEvent]) -> anyhow::Result<()> {
        let outputs = self
            .active_stage
            .process_fastpath_input(&mut self.image, events)?;
        for out in outputs {
            match out {
                ActiveStageOutput::ResponseFrame(frame) => self.framed.write_all(&frame)?,
                ActiveStageOutput::Terminate(_) => anyhow::bail!("session terminated while sending input"),
                _ => {}
            }
        }
        Ok(())
    }
}

/// Connect, wait until `ready` (or `wait`), return the live session (T1-IN-01 FastPath).
#[allow(dead_code)]
pub fn connect_until(
    host: &str,
    port: u16,
    username: &str,
    password: &str,
    width: u16,
    height: u16,
    wait: Duration,
    ready: impl Fn(&[u8]) -> bool,
) -> anyhow::Result<ActiveClient> {
    let config = connector::Config {
        credentials: ClientCredentials::UsernamePassword {
            username: username.to_owned(),
            password: password.to_owned(),
        },
        domain: None,
        enable_tls: false,
        enable_credssp: true,
        keyboard_type: KeyboardType::IbmEnhanced,
        keyboard_subtype: 0,
        keyboard_layout: 0,
        keyboard_functional_keys_count: 12,
        ime_file_name: String::new(),
        dig_product_id: String::new(),
        desktop_size: connector::DesktopSize { width, height },
        bitmap: None,
        client_build: 0,
        client_name: "mrdpd-e2e".to_owned(),
        client_dir: "C:\\Windows\\System32\\mstscax.dll".to_owned(),
        platform: MajorPlatformType::MACINTOSH,
        enable_server_pointer: false,
        request_data: None,
        autologon: false,
        enable_audio_playback: false,
        compression_type: Some(CompressionType::Rdp61),
        pointer_software_rendering: true,
        multitransport_flags: None,
        performance_flags: PerformanceFlags::default(),
        desktop_scale_factor: 0,
        hardware_id: None,
        license_cache: None,
        timezone_info: TimezoneInfo::default(),
        alternate_shell: String::new(),
        work_dir: String::new(),
    };

    let (connection_result, framed) = connect(config, host.to_owned(), port)?;
    let image = DecodedImage::new(
        ironrdp::graphics::image_processing::PixelFormat::RgbA32,
        connection_result.desktop_size.width,
        connection_result.desktop_size.height,
    );
    run_until_ready(connection_result, framed, image, wait, ready)
}

/// Screenshot until `ready` is true or `wait` elapses. Image is RgbA32.
#[allow(dead_code)]
pub fn screenshot(
    host: &str,
    port: u16,
    username: &str,
    password: &str,
    width: u16,
    height: u16,
    wait: Duration,
    ready: impl Fn(&[u8]) -> bool,
) -> anyhow::Result<Vec<u8>> {
    let client = connect_until(host, port, username, password, width, height, wait, ready)?;
    Ok(client.image.data().to_vec())
}

fn connect(
    config: connector::Config,
    server_name: String,
    port: u16,
) -> anyhow::Result<(connector::ConnectionResult, UpgradedFramed)> {
    use std::net::ToSocketAddrs as _;
    let server_addr = (server_name.as_str(), port)
        .to_socket_addrs()?
        .next()
        .context("socket address")?;
    let tcp_stream = TcpStream::connect_timeout(&server_addr, Duration::from_secs(5))?;
    tcp_stream.set_read_timeout(Some(Duration::from_millis(1500)))?;
    tcp_stream.set_write_timeout(Some(Duration::from_secs(5)))?;
    let client_addr = tcp_stream.local_addr()?;
    let mut framed = ironrdp_blocking::Framed::new(tcp_stream);
    let mut connector = connector::ClientConnector::new(config, client_addr);
    let should_upgrade = ironrdp_blocking::connect_begin(&mut framed, &mut connector)?;
    let initial_stream = framed.into_inner_no_leftover();
    let (upgraded_stream, server_public_key) = tls_upgrade(initial_stream, server_name.clone())?;
    let upgraded = ironrdp_blocking::mark_as_upgraded(should_upgrade, &mut connector);
    let mut upgraded_framed = ironrdp_blocking::Framed::new(upgraded_stream);
    let mut network_client = ReqwestNetworkClient;
    let connection_result = ironrdp_blocking::connect_finalize(
        upgraded,
        connector,
        &mut upgraded_framed,
        &mut network_client,
        server_name.into(),
        server_public_key,
        None,
    )?;
    Ok((connection_result, upgraded_framed))
}

fn run_until_ready(
    connection_result: connector::ConnectionResult,
    mut framed: UpgradedFramed,
    mut image: DecodedImage,
    wait: Duration,
    ready: impl Fn(&[u8]) -> bool,
) -> anyhow::Result<ActiveClient> {
    let mut active_stage = ActiveStageBuilder {
        static_channels: connection_result.static_channels,
        user_channel_id: connection_result.user_channel_id,
        io_channel_id: connection_result.io_channel_id,
        message_channel_id: connection_result.message_channel_id,
        share_id: connection_result.share_id,
        compression_type: connection_result.compression_type,
        enable_server_pointer: connection_result.enable_server_pointer,
        pointer_software_rendering: connection_result.pointer_software_rendering,
    }
    .build();

    let deadline = std::time::Instant::now() + wait;
    loop {
        if std::time::Instant::now() > deadline {
            break;
        }
        let (action, payload) = match framed.read_pdu() {
            Ok((action, payload)) => (action, payload),
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => continue,
            Err(e) if e.kind() == std::io::ErrorKind::TimedOut => continue,
            Err(e) => return Err(anyhow::Error::new(e).context("read frame")),
        };
        let outputs = active_stage.process(&mut image, action, &payload)?;
        for out in outputs {
            match out {
                ActiveStageOutput::ResponseFrame(frame) => framed.write_all(&frame)?,
                ActiveStageOutput::Terminate(_) => {
                    return Ok(ActiveClient {
                        active_stage,
                        framed,
                        image,
                    });
                }
                _ => {}
            }
        }
        if ready(image.data()) {
            break;
        }
    }
    Ok(ActiveClient {
        active_stage,
        framed,
        image,
    })
}

fn tls_upgrade(
    stream: TcpStream,
    server_name: String,
) -> anyhow::Result<(rustls::StreamOwned<rustls::ClientConnection, TcpStream>, Vec<u8>)> {
    let mut config = rustls::client::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(std::sync::Arc::new(danger::NoCertificateVerification))
        .with_no_client_auth();
    config.key_log = std::sync::Arc::new(rustls::KeyLogFile::new());
    config.resumption = rustls::client::Resumption::disabled();
    let config = std::sync::Arc::new(config);
    let server_name = server_name.try_into()?;
    let client = rustls::ClientConnection::new(config, server_name)?;
    let mut tls_stream = rustls::StreamOwned::new(client, stream);
    tls_stream.flush()?;
    let cert = tls_stream
        .conn
        .peer_certificates()
        .and_then(|certificates| certificates.first())
        .context("peer certificate is missing")?;
    let server_public_key = extract_tls_server_public_key(cert)?;
    Ok((tls_stream, server_public_key))
}

fn extract_tls_server_public_key(cert: &[u8]) -> anyhow::Result<Vec<u8>> {
    use x509_cert::der::Decode as _;
    let cert = x509_cert::Certificate::from_der(cert)?;
    let server_public_key = cert
        .tbs_certificate()
        .subject_public_key_info()
        .subject_public_key
        .as_bytes()
        .context("subject public key BIT STRING is not aligned")?
        .to_owned();
    Ok(server_public_key)
}

mod danger {
    use tokio_rustls::rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
    use tokio_rustls::rustls::{DigitallySignedStruct, Error, SignatureScheme, pki_types};

    #[derive(Debug)]
    pub(super) struct NoCertificateVerification;

    impl ServerCertVerifier for NoCertificateVerification {
        fn verify_server_cert(
            &self,
            _: &pki_types::CertificateDer<'_>,
            _: &[pki_types::CertificateDer<'_>],
            _: &pki_types::ServerName<'_>,
            _: &[u8],
            _: pki_types::UnixTime,
        ) -> Result<ServerCertVerified, Error> {
            Ok(ServerCertVerified::assertion())
        }

        fn verify_tls12_signature(
            &self,
            _: &[u8],
            _: &pki_types::CertificateDer<'_>,
            _: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, Error> {
            Ok(HandshakeSignatureValid::assertion())
        }

        fn verify_tls13_signature(
            &self,
            _: &[u8],
            _: &pki_types::CertificateDer<'_>,
            _: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, Error> {
            Ok(HandshakeSignatureValid::assertion())
        }

        fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
            vec![
                SignatureScheme::RSA_PKCS1_SHA256,
                SignatureScheme::ECDSA_NISTP256_SHA256,
                SignatureScheme::RSA_PKCS1_SHA384,
                SignatureScheme::ECDSA_NISTP384_SHA384,
                SignatureScheme::RSA_PKCS1_SHA512,
                SignatureScheme::ECDSA_NISTP521_SHA512,
                SignatureScheme::RSA_PSS_SHA256,
                SignatureScheme::RSA_PSS_SHA384,
                SignatureScheme::RSA_PSS_SHA512,
                SignatureScheme::ED25519,
            ]
        }
    }
}
