# Custom Odoo Addons

Place third-party Odoo 18 addon directories here so they are mounted into the Odoo container at `/mnt/extra-addons`.

Example layout:

```text
custom-addons/base_accounting_kit/__manifest__.py
custom-addons/base_accounting_kit/models/
custom-addons/base_accounting_kit/views/
```

After copying or extracting an addon, redeploy:

```bash
bash scripts/install/deploy.sh
```

Then update the Apps List in Odoo and install the module from Apps.

Do not commit downloaded third-party module code unless its license permits redistribution. This directory ignores addon contents by default; only force-add module code after confirming the license allows it.
