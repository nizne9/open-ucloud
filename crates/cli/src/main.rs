#[tokio::main]
async fn main() {
    std::process::exit(open_cloud_cli::run().await);
}
