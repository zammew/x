#!/bin/bash
# set $password for global use

# cmd anatomy: x.sh <opt_find_looper> <cmd> <opt_filename>

ask_password() {
  if [ -z "$password" ]; then
  read -s -p "Enter password: " password
  echo
fi
}

# Ask for password twice and verify they match
# Halts script execution if passwords don't match
ask_password_twice_matching() {
  if [ -z "$password" ]; then
    local password1 password2
    read -s -p "Enter password: " password1
    echo
    read -s -p "Confirm password: " password2
    echo
    
    if [ "$password1" != "$password2" ]; then
      echo "Error: Passwords do not match"
      exit 1
    fi
    
    password="$password1"
  fi
}

# test Function that reuses the PASSWORD variable
use_password() {
  ask_password
  echo "password is:" 
  echo "$password" 
}


encrypt() {
  ask_password
  echo "password"
  echo "$password"
  local input="$1"
  local output
  # Check if filename ends with .js or .ts
  # Special handling for JavaScript and TypeScript files
  if [[ "$input" == *.js || "$input" == *.ts ]]; then
    # For JavaScript and TypeScript files, append ".enc" extension
    output="${input}.enc"
  else
    # For other file types, append ".enc" extension
    output="${input}.enc"
  fi

  # Validate input file exists before attempting encryption
  # Fail early if file not found to prevent unnecessary processing
  if [[ ! -f "$input" ]]; then
    echo "File not found: $input"
    return 1  # Return error code
  fi

 if [[ -z "$password" ]]; then
    echo "Password is not set"
    return 1  # or exit 1 if you want to stop the script entirely
  fi

    echo "$password" | openssl enc -aes-256-cbc -nosalt -pass stdin -in "$input" -out "$output" -pass stdin
  # Use PASSWORD environment variable if it exists, otherwise prompt for password
 
  echo "Encrypted to: $output"
}

decrypt() {
  ask_password
  local input="$1"
  # remove .enc if present, for output filename
  local output="${input%.enc}"
  # add .enc if not present, for input filename
  local enc_input="${input%.enc}.enc"
  # Create a temporary output file to prevent corruption of existing files
  local temp_output="${output}.tmp"

  # Validate encrypted input file exists before attempting decryption
  # This ensures we're working with a valid file and prevents openssl errors
  if [[ ! -f "$enc_input" ]]; then
    echo "File not found: $enc_input"
    return 1  # Return error code
  fi

  # Remove any existing temporary file
  rm -f "$temp_output" 2>/dev/null

  # Decrypt to temporary file first
  local decrypt_status=0
  if [[ -n "$password" ]]; then
    # Pass password via stdin to avoid showing it in process list
    echo "$password" | openssl enc -aes-256-cbc -d -pass stdin -in "$enc_input" -out "$temp_output" -pass stdin || decrypt_status=$?
  else
    # No PASSWORD set, prompt user for password
    openssl enc -aes-256-cbc -d -in "$enc_input" -out "$temp_output" || decrypt_status=$?
  fi

  # Check if decryption was successful
  if [[ $decrypt_status -ne 0 ]]; then
    echo "Decryption failed: Wrong password or corrupted file"
    rm -f "$temp_output" 2>/dev/null  # Clean up temporary file
    return 1
  fi

  # Verify the temporary file exists and has content
  if [[ ! -f "$temp_output" || ! -s "$temp_output" ]]; then
    echo "Decryption failed: Output file is empty or not created"
    rm -f "$temp_output" 2>/dev/null  # Clean up temporary file
    return 1
  fi

  # Move temporary file to final destination
  mv "$temp_output" "$output"
  echo "Decrypted to: $output"
  return 0
}

# enc using openssl aes 256 cbc no salt, stdin pass 
encbase(){
  ask_password
  local input_file="$1"
  local output_file="$2"
  openssl enc -aes-256-cbc -nosalt -pass "pass:$password" -in "$input_file" -out "$output_file"
}
# dec using openssl aes 256 cbc no salt, stdin pass
decbase(){
  ask_password
  local input_file="$1"
  local output_file="$2"
  openssl enc -d -aes-256-cbc -nosalt -pass "pass:$password" -in "$input_file" -out "$output_file"
}

# enc using openssl aes 256 cbc no salt, stdin pass, encrypts filename with .renameenc
encname(){
  ask_password
  local input_file="$1"
  local output_file="$2"
  
  # Extract filename and directory
  local filename=$(basename "$input_file")
  local dir=$(dirname "$input_file")
  
  # Encrypt the filename
  local encrypted_filename=$(echo -n "$filename" | openssl enc -aes-256-cbc -nosalt -pass "pass:$password" | xxd -p | tr -d '\n')
  
  # Construct the new output filename with .renameenc extension
  local new_output_filename="$dir/${encrypted_filename}.renameenc"
  
  # Encrypt the file content
  openssl enc -aes-256-cbc -nosalt -pass "pass:$password" -in "$input_file" -out "$new_output_filename"
  echo "Encrypted file and renamed to: $new_output_filename"
}

# encname() but delete file if success encrypted. else exit early
encnamedelinput(){
  ask_password
  local input_file="$1"
  local output_file="$2"
  
  # Extract filename and directory
  local filename=$(basename "$input_file")
  local dir=$(dirname "$input_file")
  
  # Encrypt the filename
  local encrypted_filename=$(echo -n "$filename" | openssl enc -aes-256-cbc -nosalt -pass "pass:$password" | xxd -p | tr -d '\n')
  
  # Construct the new output filename with .renameenc extension
  local new_output_filename="$dir/${encrypted_filename}.renameenc"
  
  # Encrypt the file content
  if openssl enc -aes-256-cbc -nosalt -pass "pass:$password" -in "$input_file" -out "$new_output_filename"; then
    # Delete input file if encryption was successful
    rm "$input_file"
    echo "Encrypted file and renamed to: $new_output_filename"
  else
    echo "Encryption failed"
    exit 1  # Exit early on failure
  fi
}

# decname() but delete file if success encrypted. else exit early
decnamedelinput(){
  ask_password
  local input_file="$1"
  local output_file="$2"
  
  # Extract filename and directory
  local filename=$(basename "$input_file")
  local dir=$(dirname "$input_file")
  
  # Remove .renameenc extension
  local encrypted_filename_no_ext="${filename%.renameenc}"
  
  # Decrypt the filename
  local decrypted_filename=$(echo -n "$encrypted_filename_no_ext" | xxd -r -p | openssl enc -d -aes-256-cbc -nosalt -pass "pass:$password")
  
  # Construct the new output filename
  local new_output_filename="$dir/${decrypted_filename}"
  
  # Decrypt the file content
  if openssl enc -d -aes-256-cbc -nosalt -pass "pass:$password" -in "$input_file" -out "$new_output_filename"; then
    # Delete input file if decryption was successful
    rm "$input_file"
    echo "Decrypted file and renamed to: $new_output_filename"
  else
    echo "Decryption failed"
    exit 1  # Exit early on failure
  fi
}

# dec using openssl aes 256 cbc no salt, stdin pass, decrypts filename from .renameenc
decname(){
  ask_password
  local input_file="$1"
  local output_file="$2"
  
  # Extract filename and directory
  local filename=$(basename "$input_file")
  local dir=$(dirname "$input_file")
  
  # Remove .renameenc extension
  local encrypted_filename_no_ext="${filename%.renameenc}"
  
  # Decrypt the filename
  local decrypted_filename=$(echo -n "$encrypted_filename_no_ext" | xxd -r -p | openssl enc -d -aes-256-cbc -nosalt -pass "pass:$password")
  
  # Construct the new output filename
  local new_output_filename="$dir/${decrypted_filename}"
  
  # Decrypt the file content
  openssl enc -d -aes-256-cbc -nosalt -pass "pass:$password" -in "$input_file" -out "$new_output_filename"
  echo "Decrypted file and renamed to: $new_output_filename"
}


# final enc
enc(){
  # encryption requires care
  ask_password_twice_matching
loopall encnamedelinput
# loopall encname
}

# final dec
dec(){
  ask_password
 looprenameenc decnamedelinput
#  looprenameenc decname
 }

loopjs() {
  ask_password
  local cmder="$1"
  for file in ./*.js; do
    # Check if any .js files exist
    [ -e "$file" ] || continue
    "$cmder" "$file"
  done
}
loopall() {
  ask_password
  local cmder="$1"
 find . -type f -name "*.mp4"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.js"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.jsx"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.ts"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.tsx"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.json"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.md"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.png"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.jpg"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.cjs"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.astro"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
 find . -type f -name "*.bash"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
}
looprenameenc() {
  ask_password
  local cmder="$1"
  find . -type f -name "*.renameenc"  -not -path "*/.*/*" -print0 | while IFS= read -r -d '' file; do
    "$cmder" "$file"
  done
}


"$@"
