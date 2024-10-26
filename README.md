powershell

```
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/yusa-imit/zr/main/install.ps1" -OutFile install.ps1
.\install.ps1
```

sh

```
# curl을 사용하는 경우
curl -fsSL https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sudo bash

# wget을 사용하는 경우
wget -qO- https://raw.githubusercontent.com/yusa-imit/zr/main/install.sh | sudo bash
```
