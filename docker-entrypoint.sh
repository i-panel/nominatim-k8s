#!/bin/bash

if [ "$NOMINATIM_MODE" != "CREATE" ] && [ "$NOMINATIM_MODE" != "RESTORE" ]; then
    # Default to CREATE
    NOMINATIM_MODE="CREATE"
fi

# Defaults
NOMINATIM_DATA_PATH=${NOMINATIM_DATA_PATH:="/srv/nominatim/data"}
NOMINATIM_DATA_LABEL=${NOMINATIM_DATA_LABEL:="data"}
NOMINATIM_PBF_URL=${NOMINATIM_PBF_URL:="http://download.geofabrik.de/asia/maldives-latest.osm.pbf"}
NOMINATIM_POSTGRESQL_DATA_PATH=${NOMINATIM_POSTGRESQL_DATA_PATH:="/var/lib/postgresql/9.5/main"}
# S3 variables
NOMINATIM_AWS_ACCESS_KEY_ID=${NOMINATIM_AWS_ACCESS_KEY_ID:=""}
NOMINATIM_AWS_SECRET_ACCESS_KEY=${NOMINATIM_AWS_SECRET_ACCESS_KEY:=""}
NOMINATIM_AWS_REGION=${NOMINATIM_AWS_REGION:=""}
NOMINATIM_S3_BUCKET=${NOMINATIM_S3_BUCKET:=""}
NOMINATIM_PG_THREADS=${NOMINATIM_PG_THREADS:=2}

if [ "$NOMINATIM_MODE" == "CREATE" ]; then

    # Retrieve the PBF file
    curl -L $NOMINATIM_PBF_URL --create-dirs -o $NOMINATIM_DATA_PATH/$NOMINATIM_DATA_LABEL.osm.pbf
    # Allow user accounts read access to the data
    chmod 755 $NOMINATIM_DATA_PATH

    # Start PostgreSQL
    service postgresql start

    # Import data
    sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='nominatim'" | grep -q 1 || sudo -u postgres createuser -s nominatim
    sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='www-data'" | grep -q 1 || sudo -u postgres createuser -SDR www-data
    sudo -u postgres psql postgres -c "DROP DATABASE IF EXISTS nominatim"
    useradd -m -p password1234 nominatim
    sudo -u nominatim /srv/nominatim/build/utils/setup.php --osm-file $NOMINATIM_DATA_PATH/$NOMINATIM_DATA_LABEL.osm.pbf --all --threads $NOMINATIM_PG_THREADS

    if [ -n "$NOMINATIM_AWS_ACCESS_KEY_ID" ] && [ -n "$NOMINATIM_AWS_SECRET_ACCESS_KEY" ] && [ -n "$NOMINATIM_S3_BUCKET" ]; then

        # Stop PostgreSQL
        service postgresql stop

        # Archive PostgreSQL data
        tar cz $NOMINATIM_POSTGRESQL_DATA_PATH | split -b 1024MiB - $NOMINATIM_DATA_PATH/$NOMINATIM_DATA_LABEL.tgz_

        # Configure AWS CLI
        export AWS_ACCESS_KEY_ID=$NOMINATIM_AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY=$NOMINATIM_AWS_SECRET_ACCESS_KEY
        export AWS_DEFAULT_REGION=$NOMINATIM_AWS_REGION

        # Copy the archive to storage
        aws s3 cp $NOMINATIM_DATA_PATH/ s3://$NOMINATIM_S3_BUCKET/$NOMINATIM_DATA_LABEL/ --recursive --exclude "*" --include "*.tgz*"

        # Start PostgreSQL
        service postgresql start

    fi

else

    if [ -n "$NOMINATIM_AWS_ACCESS_KEY_ID" ] && [ -n "$NOMINATIM_AWS_SECRET_ACCESS_KEY" ] && [ -n "$NOMINATIM_S3_BUCKET" ]; then

        # Configure AWS CLI
        export AWS_ACCESS_KEY_ID=$NOMINATIM_AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY=$NOMINATIM_AWS_SECRET_ACCESS_KEY
        export AWS_DEFAULT_REGION=$NOMINATIM_AWS_REGION

        # Copy the archive from storage
        mkdir -p $NOMINATIM_DATA_PATH
        aws s3 cp s3://$NOMINATIM_S3_BUCKET/$NOMINATIM_DATA_LABEL/ $NOMINATIM_DATA_PATH/ --recursive --exclude "*" --include "*.tgz*"

        # Remove any files present in the target directory
        rm -rf ${NOMINATIM_POSTGRESQL_DATA_PATH:?}/*

        # Extract the archive
        cat $NOMINATIM_DATA_PATH/$NOMINATIM_DATA_LABEL.tgz_* | tar xz -C $NOMINATIM_POSTGRESQL_DATA_PATH --strip-components=5

        # Start PostgreSQL
        service postgresql start

    fi

fi

# Tail Apache logs
tail -f /var/log/apache2/* &

# Run Apache in the foreground
/usr/sbin/apache2ctl -D FOREGROUND
