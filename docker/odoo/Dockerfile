FROM odoo:18.0

USER root

# Install additional system packages needed at runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Create directory for extra addons (custom modules go here)
RUN mkdir -p /mnt/extra-addons \
    && chown -R odoo:odoo /mnt/extra-addons

# Ensure runtime directories exist with correct ownership
RUN mkdir -p /var/lib/odoo/filestore \
    && mkdir -p /var/lib/odoo/sessions \
    && mkdir -p /var/log/odoo \
    && chown -R odoo:odoo /var/lib/odoo \
    && chown -R odoo:odoo /var/log/odoo

# Copy the custom entrypoint that injects secrets into the config at runtime
COPY entrypoint.sh /custom-entrypoint.sh
RUN chmod +x /custom-entrypoint.sh

# Python dependencies required by base_accounting_kit
RUN pip3 install --no-cache-dir \
    openpyxl \
    ofxparse \
    qifparse \
    --break-system-packages

USER odoo

EXPOSE 8069 8071 8072

ENTRYPOINT ["/custom-entrypoint.sh"]
CMD ["odoo"]
