"""CLI entrypoint for the application."""

import click


@click.command()
@click.option("--name", default="World", help="Name to greet")
def main(name: str) -> None:
    """Simple greeting CLI application."""
    click.echo(f"Hello, {name}!")


if __name__ == "__main__":
    main()
