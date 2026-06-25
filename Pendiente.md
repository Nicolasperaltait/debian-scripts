1. poner este archivo en git ignore
2. dejar un .sh en el repo para correr el lo siguiente 

``` bash 


sudo bash main.sh --dry-run \
  --user operador \
  --preset gui-low-resource \
  --mode gui \
  --desktop lxqt \
  --profile baja \
  --components tools,desktop,optimization,firewall,auto-updates,hardening,audit \
  --extras ssh,zsh,clamav,rkhunter \
  --yes



```

3 no deberia nombrar el c200



