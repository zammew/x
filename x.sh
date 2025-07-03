#!/bin/bash
# set $password for global use
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

# encrypt() but removes the original file only if encryption succeeds
encryptrm() {
  local input="$1"
  local output
  
   # Determine output filename based on input filename pattern
   # For files with ".dec." pattern, we preserve it and add ".enc" extension
   if [[ "$input" == *".dec."* ]]; then
     # Keep the ".dec." in the filename and add ".enc" extension
     output="${input}.enc"
   else
     # For regular files, simply append ".enc" extension
     output="${input}.enc"
   fi
   
   # Attempt encryption and capture its return status
   # The encrypt function will handle the actual encryption process
   if encrypt "$input"; then
     # Verify encryption succeeded by checking if output file exists and has content
     # Both conditions must be true to consider encryption successful
     if [[ -f "$output" && -s "$output" ]]; then
       rm "$input"  # Safe to remove original file only after successful encryption
       echo "Original file removed: $input"
     else
       # This case handles when encrypt() returns success but output is missing/empty
       # This could happen with permission issues or disk space problems
       echo "Warning: Encryption may have failed. Original file preserved."
     fi
   else
     # This case handles when encrypt() explicitly returns an error code
     # Could be due to file not found, permission issues, or encryption errors
     echo "Encryption failed. Original file preserved."
   fi
}

# decrypt() but removes the original file only if decryption succeeds
decryptrm() {
  local input="$1"
  local output="${input%.enc}"
  local enc_input="${input%.enc}.enc"
  
  if decrypt "$input"; then
    # Check if output file exists and has content
    if [[ -f "$output" && -s "$output" ]]; then
      rm "$enc_input"
      echo "Encrypted file removed: $enc_input"
      return 0
    else
      echo "Warning: Decryption may have failed. Encrypted file preserved."
      return 1
    fi
  else
    echo "Decryption failed. Encrypted file preserved."
    return 1
  fi
}


# encrypt file in $1 including filename, preserving extension and adding .nameenc
encryptrmwname() {
  ask_password
  local input="$1"
  
  # Check if input file exists
  if [[ ! -f "$input" ]]; then
    echo "File not found: $input"
    return 1
  fi
  
  # Extract filename and extension
  local filename=$(basename "$input")
  local dir=$(dirname "$input")
  local extension="${filename##*.}"
  local basename="${filename%.*}"
  
  # If filename has no extension, use empty string for extension
  if [[ "$basename" == "$filename" ]]; then
    basename="$filename"
    extension=""
  else
    extension=".$extension"
  fi
  
  # Encrypt the filename using base64
  local encrypted_name=""
  encrypted_name=$(echo -n "$basename" | openssl enc -aes-256-cbc -a -nosalt -pass pass:"$password" 2>/dev/null | tr -d '\n')
  
  # Check if filename encryption succeeded
  if [[ -z "$encrypted_name" ]]; then
    echo "Filename encryption failed"
    return 1
  fi
  
  # Create new filename with encrypted name + original extension + .nameenc
  local output="$dir/${encrypted_name}${extension}.nameenc"
  
  # Encrypt the file content
  local encrypt_status=0
  if [[ -n "$password" ]]; then
    echo "$password" | openssl enc -aes-256-cbc -nosalt -pass stdin -in "$input" -out "$output" 2>/dev/null || encrypt_status=$?
  else
    openssl enc -aes-256-cbc -nosalt -in "$input" -out "$output" 2>/dev/null || encrypt_status=$?
  fi
  
  # Check if encryption succeeded
  if [[ $encrypt_status -ne 0 || ! -f "$output" || ! -s "$output" ]]; then
    echo "Encryption failed. Original file preserved."
    rm -f "$output" 2>/dev/null  # Clean up any partial output
    return 1
  fi
  
  # Remove original file only after successful encryption
  rm "$input"
  echo "Encrypted with filename to: $output"
  return 0
}

# decrypt file in $1 including filename, removing .nameenc
decryptrmwname() {
  ask_password
  local input="$1"
  
  # Check if input file exists
  if [[ ! -f "$input" ]]; then
    echo "File not found: $input"
    return 1
  fi
  
  # Check if file has .nameenc extension
  if [[ "$input" != *".nameenc" ]]; then
    echo "Error: File does not have .nameenc extension"
    return 1
  fi
  
  # Extract encrypted filename and extension
  local filename=$(basename "$input" .nameenc)
  local dir=$(dirname "$input")
  local extension=""
  
  # Extract extension if present
  if [[ "$filename" == *.* ]]; then
    extension=".${filename##*.}"
    filename="${filename%.*}"
  fi
  
  # Decrypt the filename
  local decrypted_name=""
  decrypted_name=$(echo -n "$filename" | openssl enc -aes-256-cbc -a -d -nosalt -pass pass:"$password" 2>/dev/null)
  local filename_status=$?
  
  # Check if filename decryption succeeded
  if [[ $filename_status -ne 0 || -z "$decrypted_name" ]]; then
    echo "Filename decryption failed: Wrong password or corrupted filename"
    return 1
  fi
  
  # Create output filename with decrypted name + original extension
  local output="$dir/${decrypted_name}${extension}"
  
  # Create a temporary output file
  local temp_output="${output}.tmp"
  
  # Remove any existing temporary file
  rm -f "$temp_output" 2>/dev/null
  
  # Decrypt the file content
  local decrypt_status=0
  if [[ -n "$password" ]]; then
    echo "$password" | openssl enc -aes-256-cbc -d -pass stdin -in "$input" -out "$temp_output" 2>/dev/null || decrypt_status=$?
  else
    openssl enc -aes-256-cbc -d -in "$input" -out "$temp_output" 2>/dev/null || decrypt_status=$?
  fi
  
  # Check if decryption was successful
  if [[ $decrypt_status -ne 0 ]]; then
    echo "Content decryption failed: Wrong password or corrupted file"
    rm -f "$temp_output" 2>/dev/null
    return 1
  fi
  
  # Verify the temporary file exists and has content
  if [[ ! -f "$temp_output" || ! -s "$temp_output" ]]; then
    echo "Decryption failed: Output file is empty or not created"
    rm -f "$temp_output" 2>/dev/null
    return 1
  fi
  
  # Move temporary file to final destination
  mv "$temp_output" "$output"
  rm "$input"  # Remove encrypted file after successful decryption
  echo "Decrypted with filename to: $output"
  return 0
}

# encryptrmwname() for all files that contain other files in current workdir,
encryptdirwname() {
  # Ask for password once at the beginning
  ask_password
  
  # Enable recursive globbing
  shopt -s globstar
  
  # Use shell globbing to find files
  local files=()
  
  # Add files matching each pattern
  for ext in js txt ts tsx py; do
    # Use nullglob to avoid issues when no files match
    shopt -s nullglob
    for file in **/*.$ext; do
      if [[ -f "$file" && "$file" != *".nameenc" ]]; then
        files+=("$file")
      fi
    done
    shopt -u nullglob
  done
  
  # Disable recursive globbing when done
  shopt -u globstar
  
  # Process all matching files
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No files found for encryption with filename"
    return 0
  fi
  
  echo "Found ${#files[@]} files to encrypt with filename"
  for file in "${files[@]}"; do
    echo "Processing: $file"
    encryptrmwname "$file"
  done
}

# decryptrmwname() for all files that contain other files in current workdir,
decryptdirwname() {
  # Ask for password once at the beginning
  ask_password
  
  # Enable recursive globbing and nullglob
  shopt -s globstar
  shopt -s nullglob
  
  # Use shell globbing to find files
  local files=()
  
  # Get all files with .nameenc extension recursively
  for file in **/*.nameenc; do
    if [[ -f "$file" ]]; then
      files+=("$file")
    fi
  done
  
  # Disable recursive globbing and nullglob when done
  shopt -u nullglob
  shopt -u globstar
  
  # Process all matching files
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No .nameenc files found for decryption"
    return 0
  fi
  
  echo "Found ${#files[@]} files to decrypt with filename"
  for file in "${files[@]}"; do
    echo "Processing: $file"
    decryptrmwname "$file"
  done
}

# encryptrm() for all files that contain other files in current workdir
encryptdir(){
  # Ask for password once at the beginning
  ask_password
  
  # Use while loop with find to avoid spawning new shells for each file
files=()
while IFS= read -r -d $'\0' file; do
  files+=("$file")
done < <(find . -type f \( -name "*.js" -o -name "*.txt" -o -name "*.ts" -o -name "*.tsx" -o -name "*.py" \) ! -name "*.enc" -print0 2>/dev/null)

  # Process all matching files
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No .js or .txt files found for encryption"
    return 0
  fi
  
  echo "Found ${#files[@]} files to encrypt"
  for file in "${files[@]}"; do
    echo "Processing: $file"
    encryptrm "$file"
  done
}

# decryptrm() for all files that contain .enc.
decryptdir(){
  # Ask for password once at the beginning
  ask_password
  
  # Decrypt filenames first
  
  # Use while loop with find to avoid spawning new shells for each file
  local files=()
  while IFS= read -r -d $'\0' file; do
    files+=("$file")
  done < <(find . -type f -name "*.enc" -print0)
  
  # Process all matching files
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No .enc files found for decryption"
    return 0
  fi
  
  echo "Found ${#files[@]} files to decrypt"
  local success_count=0
  local fail_count=0
  
  # Try decrypting the first file to check if password works
  if [[ ${#files[@]} -gt 0 ]]; then
    echo "Testing decryption with first file: ${files[0]}"
    if ! decryptrm "${files[0]}"; then
      echo "Warning: First file decryption failed. This may indicate an incorrect password."
      read -p "Continue with remaining files? (y/n): " continue_choice
      if [[ "$continue_choice" != "y" && "$continue_choice" != "Y" ]]; then
        echo "Decryption aborted to prevent potential data corruption."
        return 1
      fi
      ((fail_count++))
    else
      ((success_count++))
    fi
  fi
  
  # Process remaining files
  for ((i=1; i<${#files[@]}; i++)); do
    file="${files[$i]}"
    echo "Processing: $file"
    if decryptrm "$file"; then
      ((success_count++))
    else
      ((fail_count++))
    fi
  done
  
  echo "Decryption complete: $success_count files successfully decrypted, $fail_count files failed"
}

# enc using openssl aes 256 cbc no salt, stdin pass 
encbase(){
  local input_file="$1"
  local output_file="$2"
  openssl enc -aes-256-cbc -nosalt -pass stdin -in "$input_file" -out "$output_file"
}
# dec using openssl aes 256 cbc no salt, stdin pass
decbase(){
  local input_file="$1"
  local output_file="$2"
  openssl enc -d -aes-256-cbc -nosalt -pass stdin -in "$input_file" -out "$output_file"
}



# Function to encrypt a file using OpenSSL
# Usage: encrypt_file input_file output_file password
encrypt_file() {
  local input_file="$1"
  local output_file="$2"
  local password="$3"
  
  # Use OpenSSL to encrypt the file with AES-256-CBC
  openssl enc -aes-256-cbc -nosalt -in "$input_file" -out "$output_file" -pass "pass:$password" 2>/dev/null
  return $?
}

# Function to decrypt a file using OpenSSL
# Usage: decrypt_file input_file output_file password
decrypt_file() {
  local input_file="$1"
  local output_file="$2"
  local password="$3"
  
  # Use OpenSSL to decrypt the file
  openssl enc -d -aes-256-cbc -in "$input_file" -out "$output_file" -pass "pass:$password" 2>/dev/null
  return $?
}

#  Loop through all .enc files, encrypt the content with OpenSSL, and rename to hex filename
# Usage: encryptfilenameinfolder [directory]
# If directory is not specified, uses current directory
encryptfilenameinfolder(){
  ask_password
  local search_dir="${1:-.}"
  cd "$search_dir" || { echo "Error: Cannot change to directory $search_dir"; return 1; }
  
  # Ask for encryption password
  if [[ -z "$password" ]]; then
    echo "Error: Password cannot be empty"
    return 1
  fi
  
  # Enable recursive globbing
  shopt -s globstar
  
  # Use shell globbing to find files
  local files=()
  
  # Add files matching each pattern
  for ext in .enc; do
    # Use nullglob to avoid issues when no files match
    shopt -s nullglob
    for file in **/*"$ext"; do
      if [[ -f "$file" && "$file" != *".renameenc" ]]; then
        files+=("$file")
      fi
    done
    shopt -u nullglob
  done
  
  # Disable recursive globbing when done
  shopt -u globstar
  
  # Process all matching files
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No .enc files found for encryption"
    return 0
  fi
  
  echo "Found ${#files[@]} files to encrypt"
  local success_count=0
  local fail_count=0
  
  for file in "${files[@]}"; do
    # Extract filename and extension
    local filename=$(basename "$file")
    local dir=$(dirname "$file")
    local extension="${filename##*.}"
    local basename="${filename%.*}"
    
    # If filename has no extension, use empty string for extension
    if [[ "$basename" == "$filename" ]]; then
      basename="$filename"
      extension=""
    else
      extension=".$extension"
    fi
    
    # Convert filename to hex
    local hex_name=$(echo -n "$basename" | xxd -p | tr -d '\n')
    
    # Create new filename with hex name + original extension + .renameenc
    local new_name="$dir/${hex_name}${extension}.renameenc"
    
    # Create a temporary file for encryption
    local temp_file=$(mktemp)
    
    # Encrypt the file
    if encrypt_file "$file" "$temp_file" "$password"; then
      # Move the encrypted file to the final destination
      if mv "$temp_file" "$new_name"; then
        # Remove the original file only after successful encryption and move
        rm "$file"
        echo "Encrypted: $file -> $new_name"
        ((success_count++))
      else
        echo "Error: Failed to move encrypted file for $file"
        rm "$temp_file"  # Clean up temp file
        ((fail_count++))
      fi
    else
      echo "Error: Failed to encrypt $file"
      rm "$temp_file"  # Clean up temp file
      ((fail_count++))
    fi
  done
  
  echo "Encryption complete: $success_count files successfully encrypted, $fail_count files failed"
}

#  Decrypt files with .renameenc extension and restore original filenames
# Usage: decryptfilenameinfolder [directory]
# If directory is not specified, uses current directory
decryptfilenameinfolder(){
  # Ask for decryption password
  ask_password
  local search_dir="${1:-.}"
  cd "$search_dir" || { echo "Error: Cannot change to directory $search_dir"; return 1; }
  
  if [[ -z "$password" ]]; then
    echo "Error: Password cannot be empty"
    return 1
  fi
  
  # Enable recursive globbing and nullglob
  shopt -s globstar
  shopt -s nullglob
  
  # Use shell globbing to find files
  local files=()
  
  # Get all files with .renameenc extension recursively
  for file in **/*.renameenc; do
    if [[ -f "$file" ]]; then
      files+=("$file")
    fi
  done
  
  # Disable recursive globbing and nullglob when done
  shopt -u nullglob
  shopt -u globstar
  
  # Process all matching files
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No .renameenc files found for decryption"
    return 0
  fi
  
  echo "Found ${#files[@]} files to decrypt"
  local success_count=0
  local fail_count=0
  
  for file in "${files[@]}"; do
    # Extract encrypted filename and extension
    local filename=$(basename "$file" .renameenc)
    local dir=$(dirname "$file")
    local extension=""
    
    # Extract extension if present
    if [[ "$filename" == *.* ]]; then
      extension=".${filename##*.}"
      filename="${filename%.*}"
    fi
    
    # Convert hex back to original filename - capture any errors
    local original_name=""
    original_name=$(echo -n "$filename" | xxd -p -r 2>/dev/null) || {
      echo "Error: Failed to decode filename for $file"
      ((fail_count++))
      continue
    }
    
    # Verify we got a valid filename
    if [[ -z "$original_name" ]]; then
      echo "Error: Decoded filename is empty for $file"
      ((fail_count++))
      continue
    fi
    
    # Create output filename with decrypted name + original extension
    local new_name="$dir/${original_name}${extension}"
    
    # Create a temporary file for decryption
    local temp_file=$(mktemp)
    
    # Decrypt the file
    if decrypt_file "$file" "$temp_file" "$password"; then
      # Move the decrypted file to the final destination
      if mv "$temp_file" "$new_name"; then
        # Remove the encrypted file only after successful decryption and move
        rm "$file"
        echo "Decrypted: $file -> $new_name"
        ((success_count++))
      else
        echo "Error: Failed to move decrypted file for $file"
        rm "$temp_file"  # Clean up temp file
        ((fail_count++))
      fi
    else
      echo "Error: Failed to decrypt $file (wrong password?)"
      rm "$temp_file"  # Clean up temp file
      ((fail_count++))
    fi
  done
  
  echo "Decryption complete: $success_count files successfully decrypted, $fail_count files failed"
}

# final enc
enc(){
  # encryption requires care
  ask_password_twice_matching
  encryptdir
  encryptfilenameinfolder
}

# final dec
dec(){
  decryptdir
  decryptfilenameinfolder
}

"$@"
