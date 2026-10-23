use clap::Parser;

/// Greet someone.
#[derive(Debug, Parser)]
#[command(name = "my-cli", version, about)]
struct Args {
    /// Who to greet.
    #[arg(default_value = "world")]
    name: String,
}

fn main() {
    let args = Args::parse();
    println!("{}", my_lib::greet(&args.name));
}
