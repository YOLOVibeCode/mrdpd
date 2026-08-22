//! Ephemeral or file-backed TLS identity (T1-SEC-01).

use std::path::Path;

use ironrdp_server::TlsIdentityCtx;
use ironrdp_server::tokio_rustls::TlsAcceptor;

use crate::{MRDPD_ERR_CERT, MRDPD_ERR_INTERNAL};

pub struct TlsMaterial {
    pub acceptor: TlsAcceptor,
    pub pub_key: Vec<u8>,
}

impl TlsMaterial {
    pub fn from_paths(cert: &str, key: &str) -> Result<Self, i32> {
        let ctx = TlsIdentityCtx::init_from_paths(Path::new(cert), Path::new(key))
            .map_err(|_| MRDPD_ERR_CERT)?;
        let acceptor = ctx.make_acceptor().map_err(|_| MRDPD_ERR_CERT)?;
        Ok(Self {
            acceptor,
            pub_key: ctx.pub_key,
        })
    }

    pub fn ephemeral() -> Result<Self, i32> {
        let dir = tempfile::tempdir().map_err(|_| MRDPD_ERR_INTERNAL)?;
        let cert_path = dir.path().join("cert.pem");
        let key_path = dir.path().join("key.pem");
        write_ephemeral_pem(&cert_path, &key_path)?;
        Self::from_paths(
            cert_path.to_str().ok_or(MRDPD_ERR_INTERNAL)?,
            key_path.to_str().ok_or(MRDPD_ERR_INTERNAL)?,
        )
        .map_err(|_| MRDPD_ERR_INTERNAL)
    }
}

fn write_ephemeral_pem(cert_path: &Path, key_path: &Path) -> Result<(), i32> {
    let key_pair = rcgen::KeyPair::generate().map_err(|_| MRDPD_ERR_INTERNAL)?;
    let mut params =
        rcgen::CertificateParams::new(vec!["localhost".to_owned(), "127.0.0.1".to_owned()])
            .map_err(|_| MRDPD_ERR_INTERNAL)?;
    params
        .distinguished_name
        .push(rcgen::DnType::CommonName, "mrdpd-ephemeral");
    let cert = params
        .self_signed(&key_pair)
        .map_err(|_| MRDPD_ERR_INTERNAL)?;
    std::fs::write(cert_path, cert.pem()).map_err(|_| MRDPD_ERR_INTERNAL)?;
    std::fs::write(key_path, key_pair.serialize_pem()).map_err(|_| MRDPD_ERR_INTERNAL)?;
    Ok(())
}
