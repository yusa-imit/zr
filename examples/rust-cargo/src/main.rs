use clap::Parser;

mod calculator;

#[derive(Parser, Debug)]
#[command(name = "myapp")]
#[command(about = "A simple calculator CLI", long_about = None)]
struct Args {
    /// First number
    #[arg(short, long)]
    a: i32,

    /// Second number
    #[arg(short, long)]
    b: i32,

    /// Operation: add, multiply
    #[arg(short, long, default_value = "add")]
    operation: String,
}

fn main() {
    let args = Args::parse();

    let result = match args.operation.as_str() {
        "add" => calculator::add(args.a, args.b),
        "multiply" => calculator::multiply(args.a, args.b),
        _ => {
            eprintln!("Unknown operation: {}", args.operation);
            std::process::exit(1);
        }
    };

    println!("{}", result);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculator_integration() {
        assert_eq!(calculator::add(2, 3), 5);
        assert_eq!(calculator::multiply(2, 3), 6);
    }
}
