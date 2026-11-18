use clap::Parser;
use pl_model_auth::chatgpt::ChatGptAuthorization;

/// Log in with ChatGPT and verify the credential in memory.
#[derive(Parser)]
struct Args {}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    Args::parse();
    let host_id = format!("urn:uuid:{}", uuid::Uuid::new_v4());
    let authorization = ChatGptAuthorization::prepare(host_id, None).await?;
    println!(
        "Open this URL in a browser on this machine:\n{}",
        authorization.authorization_url()
    );
    authorization.finish().await?.validate()?;
    println!("ChatGPT sign-in succeeded. The credential was verified and discarded.");
    Ok(())
}
