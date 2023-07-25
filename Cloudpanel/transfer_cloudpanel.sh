#!/bin/bash -x

# Plesk server details
plesk_host="IP_ADDR"
plesk_user="USER" # Plesk user login
plesk_ftp_user="TEMP_FTP_USER" # this is created and removed for each domain
plesk_ftp_password="TEMP_FTP_PASS" #this is created and removed for each domain

phpVersion="8.2" # Change to whatever PHP version you want to use

keyPem="./PLESK_KEY.pem" # Path to the SSH KEY file


# Output directory for downloaded files and databases
output_dir="/home/ubuntu/plesk"

# Function to download files from Plesk server using FTP
download_files() {
    domain="$1"

    sudo ssh -i $keyPem "$plesk_user@$plesk_host" "sudo plesk bin ftpsubaccount --create $plesk_ftp_user -domain $domain -passwd $plesk_ftp_password -home /" 
    output_domain_dir="$output_dir/$domain"
    
    echo "DEBUG: ssh -i $keyPem \"$plesk_user@$plesk_host\" \"sudo plesk bin ftpsubaccount --create $plesk_ftp_user -domain $domain -passwd $plesk_ftp_password -home /\"" 

    sudo mkdir -p "$output_domain_dir"

    echo "Downloading files for domain: $domain"

    echo "DEBUG: ncftpget -u \"$plesk_ftp_user\" -p \"$plesk_ftp_password\" -R -V \"$plesk_host\" \"$output_domain_dir\" \"/\""
    ncftpget -u "$plesk_ftp_user" -p "$plesk_ftp_password" -R -V "$plesk_host" "$output_domain_dir" "/"

    echo "Downloading files for domain: $domain - COMPLETE"

    echo "DEBUG: sudo ssh -i $keyPem \"$plesk_user@$plesk_host\" \"sudo plesk bin ftpsubaccount --remove $plesk_ftp_user -domain $domain\""
    sudo ssh -i $keyPem "$plesk_user@$plesk_host" "sudo plesk bin ftpsubaccount --remove \"$plesk_ftp_user\" -domain \"$domain\""
}

# Function to download database from Plesk server
download_database() {

    domain="$1"
    db_name="$2"
    db_user="$3"
    tempDBPass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '');

    echo "Downloading database $db_name for domain: $domain (DB user: $db_user)"
    
    output_db_file="$output_dir/$domain/$db_name.sql"
    echo "DEBUG: sudo ssh -i \"$keyPem\" \"$plesk_user@$plesk_host\" \"sudo plesk db dump $db_name > $db_name.sql && chown $plesk_user $db_name.sql\""
    sudo ssh -i "$keyPem" "$plesk_user@$plesk_host" "sudo plesk db dump $db_name > $db_name.sql && chown $plesk_user $db_name.sql"

    echo "DEBUG: scp -i \"$keyPem\" \"$plesk_user@$plesk_host:$db_name.sql\" \"$output_db_file\""
    scp -i "$keyPem" "$plesk_user@$plesk_host:$db_name.sql" "$output_db_file"


    # Domain has a matching database, so download it.
    if [[ $db_name =~ ['!@#$%^&*()_+'] ]]; then
        echo "Database Name: $db_name contains a special character"
        db_name="${db_name//[^[:alnum:]]/"-"}"
    fi
    if [[ $db_user =~ ['!@#$%^&*()_+'] ]]; then
        echo "Database User: $db_user contains a special character"
        db_user="${db_user//[^[:alnum:]]/"-"}"
    fi

    if ($db_user = "NULL"); then
        echo "NULL DB USER FOUND - USING DB NAME AS USER";
        db_user=$db_name
    fi

    if clpctl db:add --domainName="$domain" --databaseName="$db_name" --databaseUserName="$db_user" --databaseUserPassword=''$tempDBPass''; then
        echo "DB $db_name added to $domain with username $db_user and password $tempDBPass";
        if clpctl db:import --databaseName=$db_name --file="$output_db_file"; then
            echo "DB Imported $db_name";
        else 
            echo "DB $db_name Not Imported";
        fi
    else 
        echo "DB $db_name was not created on $domain";
    fi
}

# Function to create account/domain
create_account() {
    domain="$1"
    php="$2"
    owner="$3"
    tempPass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '');

    echo "Creating account/domain for domain: $domain - Temp Pass: "

    # Create account

    clpctl site:add:php --domainName="$domain" --phpVersion="$php" --vhostTemplate='Generic' --siteUser="$owner" --siteUserPassword="$tempPass"

    # Move files to CloudPanel domain directory
    panel_dir="/home/$owner"

    sudo cp -R "$output_domain_dir/httpdocs/." "$panel_dir/htdocs/$domain/."

    echo "Created $domain successfully!"
}


# Main script

# Connect to the Plesk server and get the list of domains
domain_list=$(ssh -i "$keyPem" "$plesk_user@$plesk_host" "sudo plesk bin domain --list")

# Iterate over each domain
for domain in $domain_list; do

    # Download files from Plesk server
    download_files "$domain"

    # Create CyberPanel account/domain
    owner="${domain//./-}"

    create_account "$domain" "$phpVersion" "$owner"
    
    domain_db_list=$(ssh -i "$keyPem" "$plesk_user@$plesk_host" "sudo plesk db -N -e \"SELECT CONCAT_WS(',', db.name, IFNULL(dbu.login, 'NULL'), d.name) FROM data_bases db LEFT JOIN db_users dbu ON db.default_user_id = dbu.id LEFT JOIN domains d ON db.dom_id = d.id WHERE d.name IS NOT NULL AND d.name='$domain'\"")

    echo "Processing DB: $domain_db_list"

    # Loop through each line of the database response
    IFS=$'\n'
    for entry in $domain_db_list; do
        IFS=',' read -r db_name db_user db_domain <<< "$entry"
        if [ "$db_domain" = "$domain" ]; then
            echo "Found matching database: $db_name (user: $db_user)"
            download_database "$domain" "$db_name" "$db_user"
        fi
    done
done