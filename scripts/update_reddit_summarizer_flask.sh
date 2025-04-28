#!/bin/bash

# Set up error handling
set -e # Exit immediately if a command exits with a non-zero status

# Navigate to your project directory (change this to your actual project path if needed)
cd ~/projects/reddit-ai-summarizer-backend || exit 1

# Show current directory
echo "Current directory: $(pwd)"

# Pull latest changes from git repository
echo "Pulling latest changes from git repository..."
git pull

# Check if git pull was successful
if [ $? -eq 0 ]; then
  echo "Git pull completed successfully."
else
  echo "Error: Git pull failed. Exiting script."
  exit 1
fi

# Build the project using nixpacks
echo "Building project with nixpacks..."
sudo nixpacks build . --name reddit-summarizer-flask

# Check if build was successful
if [ $? -eq 0 ]; then
  echo "Build completed successfully."
  echo "Your container image 'reddit-summarizer-flask' is ready to use."
else
  echo "Error: Build failed."
  exit 1
fi

echo "Script completed successfully!"
