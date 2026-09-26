#[tokio::main]
async fn main() {
    std::process::exit(open_ucloud_cli::run().await);
}
