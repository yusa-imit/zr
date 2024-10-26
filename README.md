powershell

```
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/yusa-imit/zr/main/install.ps1'))
```

bash curl/wget

```
curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sudo bash
wget -qO- https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sudo bash
```
