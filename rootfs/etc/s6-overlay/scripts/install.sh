#!/command/with-contenv bash
# shellcheck shell=bash
set -e

# shellcheck disable=SC1091
source /etc/islandora/utilities.sh

readonly SITE="default"

function configure {
    # Work around for when the cache is in a bad state, as Drush will access
    # the cache before rebuilding it for some dumb reason, preventing
    # Drush from being able to clear it.
    local params=$(/var/www/drupal/web/core/scripts/rebuild_token_calculator.sh 2>/dev/null)
    curl -L "${DRUSH_OPTIONS_URI}/core/rebuild.php?${params}"
    drush --root=/var/www/drupal --uri="${DRUSH_OPTIONS_URI}" cache:rebuild
    if [ -n "${DRUPAL_DEFAULT_FCREPO_URL:-}" ]; then
      drush --root=/var/www/drupal --uri="${DRUSH_OPTIONS_URI}" user:role:add fedoraadmin admin
    fi
    drush --root=/var/www/drupal --uri="${DRUSH_OPTIONS_URI}" pm:uninstall pgsql sqlite
    drush --root=/var/www/drupal --uri="${DRUSH_OPTIONS_URI}" migrate:import --userid=1 --tag=islandora
    drush --root=/var/www/drupal --uri="${DRUSH_OPTIONS_URI}" cron || true
    drush --root=/var/www/drupal --uri="${DRUSH_OPTIONS_URI}" search-api:index || true
    drush --root=/var/www/drupal --uri="${DRUSH_OPTIONS_URI}" cache:rebuild
}

function install {
    # wait for mariadb, activemq, and solr to be available
    wait_for_service "${SITE}" db
    wait_for_service "${SITE}" broker
    wait_for_service "${SITE}" solr

    # if fcrepo is enabled, wait for it
    if [ -n "${DRUPAL_DEFAULT_FCREPO_URL:-}" ]; then
        wait_for_service "${SITE}" fcrepo
    fi

    create_database "${SITE}"
    install_site "${SITE}"

    # if blazegraph is enabled, create its namespace
    if [ -n "${DRUPAL_DEFAULT_TRIPLESTORE_NAMESPACE:-}" ]; then
        wait_for_service "${SITE}" triplestore
        create_blazegraph_namespace_with_default_properties "${SITE}"
    fi

    # if fcrepo is served over TLS
    # certs might need to be generated from letsencrypt which can take a minute or more.    
    if [[ "${DRUPAL_DEFAULT_FCREPO_URL:-}" == https* ]]; then
        end=$((SECONDS+300))
        while (( SECONDS < end )); do
            if curl -s -o /dev/null -X HEAD "${DRUPAL_DEFAULT_FCREPO_URL}"; then
                echo "Valid certificate"
                break
            fi
    
            echo "Waiting for valid certificate..."
            sleep 5
        done
        if (( SECONDS >= end )); then
            echo "Invalid certificate for ${DRUPAL_DEFAULT_FCREPO_URL}"
            exit 1
        fi
    fi

    configure
}

function mysql_count_query {
    cat <<-EOF
SELECT COUNT(DISTINCT table_name)
FROM information_schema.columns
WHERE table_schema = '${DRUPAL_DEFAULT_DB_NAME}';
EOF
}

# Check the number of tables to determine if it has already been installed.
function installed {
    local count
    count=$(execute-sql-file.sh <(mysql_count_query) -- -N 2>/dev/null) || exit $?
    [[ $count -ne 0 ]]
}

# Required even if not installing.
function setup() {
    local site drupal_root subdir site_directory public_files_directory private_files_directory twig_cache_directory
    site="${1}"
    shift

    drupal_root=/var/www/drupal/web
    subdir=$(drupal_site_env "${site}" "SUBDIR")
    site_directory="${drupal_root}/sites/${subdir}"
    public_files_directory="${site_directory}/files"
    private_files_directory="/var/www/drupal/private"
    twig_cache_directory="${private_files_directory}/php"

    # Ensure the files directories are writable by nginx, as when it is a new volume it is owned by root.
    mkdir -p "${site_directory}" "${public_files_directory}" "${private_files_directory}" "${twig_cache_directory}"
    chown nginx:nginx "${site_directory}" "${public_files_directory}" "${private_files_directory}" "${twig_cache_directory}"
    chmod ug+rw "${site_directory}" "${public_files_directory}" "${private_files_directory}" "${twig_cache_directory}"
}

function drush_cache_setup {
    # Make sure the default drush cache directory exists and is writeable.
    mkdir -p /tmp/drush-/cache
    chmod a+rwx /tmp/drush-/cache
}

# External processes can look for `/installed` to check if installation is completed.
function finished {
    touch /installed
    cat <<-EOT


#####################
# Install Completed #
#####################
EOT
}

function main() {
    cd /var/www/drupal
    drush_cache_setup
    for_all_sites setup

    if installed; then
        echo "Already Installed"
    else
        echo "Installing"
        install
    fi
    finished
}
main
