export GANDI_LIVEDNS_KEY=$(<.gandi-api-key)

successful=true
acme="$HOME/.acme.sh/acme.sh"
reload_nginx=false
while IFS=";" read -r dn subs
do
    echo "Domain: $dn"
    
    exists=true
    directory="/etc/nginx/certs/$dn"
    certificate="$directory/cert.pem"
    if [ ! -d "$directory" ]; then
        mkdir "$directory"
        exists=false
    elif [ ! -f "$certificate" ]; then
        exists=false
    fi

    options="-d \"$dn\""
    IFS=","
    read -ra sdns <<< "$subs"
    for sdn in "${sdns[@]}"; do
        options+=" -d \"$sdn.$dn\""
    done

    updated=false
    if [ "$exists" = false ]; then
        echo "Issuing certificate..."
        eval "$acme --issue --dns dns_gandi_livedns $options"

        if [ "$?" = "0" ]; then
            updated=true
        else
            echo "Failed to issue certificate."
            successful=false
        fi
    else
        openssl x509 -checkend 172800 -noout -in $certificate > /dev/null

        if [ "$?" = "1" ]; then
            echo "Renewing certificate..."
            eval "$acme --renew --dns dns_gandi_livedns $options"

            if [ "$?" = "0" ]; then
                updated=true
            else
                echo "Failed to renew certificate"
                successful=false
            fi
        fi
    fi

    if [ "$updated" = true ]; then
        echo "Installing certificate..."
        eval "$acme --install-cert -d $dn --key-file $directory/key.pem --fullchain-file $certificate"
        
        if [ "$?" = "0" ]; then
            reload_nginx=true
        else
            echo "Failed to install certificate."
            successful=false
        fi
    elif [ "$exists" = true ]; then
        echo "No action required."
    fi
done < domains

if [ "$reload_nginx" = true ]; then
    echo "New certificates installed, reloading nginx"
    nginx -s reload

    if [ "$?" = "0" ]; then
        echo "Successfully updated certificates"
    else
        echo "Failed to reload nginx"
        successful=false
    fi
else
    echo "No updates detected"
fi

if [ "$successful" = false ]; then
    exit 1
else
    exit 0
fi
