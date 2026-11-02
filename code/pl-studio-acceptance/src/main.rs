fn main() -> anyhow::Result<()> {
    environment::run()
}

mod desktop;
mod environment;
mod manual_gui;
mod native;
