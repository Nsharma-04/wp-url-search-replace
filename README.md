# WordPress URL Search and Replace

A Bash utility that updates a WordPress site's URLs in its database through [WP-CLI](https://wp-cli.org/). It prompts for the old and new URLs, previews the replacement plan, and offers a dry run before writing changes.

## What it does

The script checks that WP-CLI is available and that the selected path contains an installed WordPress site. It accepts URLs with `https://`, `http://`, or no scheme, then runs three serialized-data-aware `wp search-replace` passes that preserve each source format:

1. `https://old-domain` → `https://new-domain`
2. `http://old-domain` → `http://new-domain`
3. `old-domain` → `new-domain`, to catch protocol-less occurrences

It searches all tables with the WordPress table prefix, skips the `guid` column, uses WP-CLI's precise recursive object handling, and reports changed rows. In apply mode, it offers to export a SQL database backup first, then flushes the cache and rewrite rules after replacement.

## Requirements

- Bash 4 or later
- A working WordPress installation
- WP-CLI available on `PATH`
- Database credentials configured for WP-CLI

## Usage

Run from the WordPress root:

```bash
bash wp-url-replace.sh
```

Or pass the WordPress installation path:

```bash
bash wp-url-replace.sh /var/www/html/site
```

The old URL prompt is prefilled from the WordPress `siteurl` option and remains editable; use the arrow keys to change it if needed. Enter the new URL manually. Choose **Dry run** first to preview database changes. Choose **Proceed** only after reviewing the preview and confirming the URLs. The script offers a timestamped SQL export before it writes changes.

## Notes

- Bash line editing is enabled for the URL prompts, so the left and right arrow keys can move the cursor to edit the input.
- The entered schemes choose only the domain values; replacement pairs preserve HTTPS, HTTP, and protocol-less formats respectively.
- The third pass replaces the domain text wherever it appears, including protocol-less links and text values.
- WordPress GUID values are intentionally left unchanged.
- This script changes database contents. Keep a verified backup and review the dry-run output before applying it, especially on multisite or customized installations.

