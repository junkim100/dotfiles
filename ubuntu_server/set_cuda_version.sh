#!/bin/bash

# Function to display available CUDA versions
list_cuda_versions() {
  echo "Available CUDA versions:"
  for dir in /usr/local/cuda*; do
    if [ -d "$dir" ]; then
      version=$(basename "$dir" | sed 's/cuda-//')
      echo "$version"
    fi
  done
}

# Function to prompt user to choose a CUDA version
choose_cuda_version() {
  read -p "Enter the CUDA version you would like to use: " chosen_version
  chosen_path="/usr/local/cuda-$chosen_version"
  if [ ! -d "$chosen_path" ]; then
    echo "Invalid selection. Please make sure the version exists."
    exit 1
  fi
}

# Display available CUDA versions
list_cuda_versions

# Prompt user to choose a version
choose_cuda_version

# Export PATH and LD_LIBRARY_PATH
export PATH="$chosen_path/bin:$PATH"
export LD_LIBRARY_PATH="$chosen_path/lib64:$LD_LIBRARY_PATH"

# Print the current CUDA settings
echo "CUDA version $chosen_version is now set."
echo "PATH is set to: $PATH"
echo "LD_LIBRARY_PATH is set to: $LD_LIBRARY_PATH"

# Warning message
echo "Warning: Restarting the shell will erase this setting."
