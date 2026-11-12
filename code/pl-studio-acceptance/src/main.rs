use clap::Parser;

fn main() -> anyhow::Result<()> {
    manual_gui::run(manual_gui::ManualGuiOptions::parse())
}

mod manual_gui;
