#[cfg(target_os = "linux")]
#[tokio::main]
async fn main() {
    if let Err(error) = pl_studio_update::linux::run_helper().await {
        eprintln!("anywork update helper: {error}");
        std::process::exit(1);
    }
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("the update helper is Linux-only");
    std::process::exit(1);
}
