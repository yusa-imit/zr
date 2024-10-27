# ZR (t͡ɕiɾa̠ɭ)

Ultimate Language Agnostic Command Running Solution written in Zig

### Usage

```
    Usage:
        zr <command> [arguments]
    Commands:
        init                  Create initial config file
        run <repo> <command>  Run command in specified repository
        list                  List all repositories
        add <name> <path>     Add a new repository
        remove <name>         Remove a repository
        help                  Show this help message
        <repo> <task>         Run config > Repository defined tasks

    Examples:
        zr init
        zr add frontend ./packages/frontend
        zr run frontend npm start

```

## Install

For alpha period, only command line install will be provided.

#### Windows

powershell

```
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/yusa-imit/zr/main/install.ps1'))
```

#### Posix

bash curl/wget

```
curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sudo bash
wget -qO- https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sudo bash
```

## How to write `.zr.config.yaml`

See [.zr.config.spec.yaml](https://github.com/yusa-imit/zr/blob/v0.0.3/.zr.config.spec.yaml)
