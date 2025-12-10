#!/bin/bash

#determine OS Name
os=$(uname)

#Update
if [ "$os" = "Linux" ]; then

  echo "OS: $os"

  if [[ -f /etc/redhat-release ]]; then
     pkg_manager=yum
  elif [[ -f /etc/debian_version ]]; then
     pkg_manager=apt
  fi


  if [ "$pkg_manager" = "yum" ]; then
     sudo yum update -y
  elif [ "$pkg_manager" = "apt" ]; then
     sudo apt update && sudo apt upgrade -y
  fi

elif [ "$os" = "Darwin" ]; then
  echo "OS: $os"
    brew install git

else
  echo"Unsupported OS"
  exit 1

fi

echo "Success Installed Update"


installDocker(){
   echo "Installing docker..."
   sudo apt install -y ca-certificates curl gnupg lsb-release
   curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list> /dev/null
   echo "Update package..."
   sudo apt update
   echo "Installing Docker..."
   sudo apt install -y docker-ce docker-ce-cli containerd.io
   sudo usermod -aG docker "$USER"
   echo "Installation Finished"
}

#grant execution permission to run scirpt
chmod +x script.sh

#testing configuration

#echo "Testing git configurations"

#if git --version >/dev/null 2>&1; then
#   echo "Git success configured"
#else 
#   echo "Git failed to configured"
#fi

installDocker
