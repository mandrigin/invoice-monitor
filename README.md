# Invoice Filer

A macOS menu bar application for automatic invoice organization and generation.

> This app was vibe-coded with Claude

## Overview

Invoice Filer is a dual-purpose macOS app that:

1. **Automatically organizes incoming invoices** - Monitors directories for PDF and image files, uses OCR to identify invoices, matches them to configured companies, and files them into organized folders.

2. **Generates recurring invoices** - Creates draft invoices from templates on a configurable schedule, with intelligent due date calculation that accounts for bank holidays.

## Features

### Invoice Filing & Organization

- **Directory Monitoring**: Watch one or more directories for new invoice files
- **OCR Processing**: Extracts text from PDFs and images using macOS Vision framework
- **Company Matching**: Identifies companies via names, aliases, tax IDs, and email domains
- **Smart Filing**: Organizes invoices into year/month folders by extracted date
- **Configurable Thresholds**: Adjust confidence levels for invoice classification and company matching

**Supported file formats**: PDF, PNG, JPG, JPEG, HEIC, WebP, TIFF

### Invoice Generation

- **Templates**: Create reusable invoice templates for recurring billing
- **Automatic Scheduling**: Generate draft invoices on your specified billing day each month
- **Bank Holiday Support**: Due dates automatically adjust to avoid weekends and bank holidays in both sender and recipient countries
- **Draft Management**: Review, edit, approve, and track invoice drafts
- **PDF Export**: Export invoices to PDF with automatic folder organization

### Menu Bar Integration

- **Status Indicator**: Color-coded badge shows current state (green=idle, yellow=processing, red=error)
- **Quick Stats**: View filing statistics from the last 24 hours
- **One-Click Access**: Open Invoice Management, Log Viewer, or Preferences directly from the menu

### Additional Features

- Launch at login
- Detailed JSONL logging
- Full Disk Access permission handling
- Exclusion patterns for unwanted files
- Debounce interval to avoid processing partial downloads

## Configuration

### App Config Location

Configuration is stored in:
```
~/Library/Application Support/InvoiceFiler/config.json
```

### Monitored Paths

Add directories to watch for incoming invoices. Each path can be:
- **Recursive**: Monitor subdirectories too
- **Non-recursive**: Only watch the specified directory

### Companies

Configure companies to match against invoice content:

| Field | Description |
|-------|-------------|
| Name | Primary company name |
| Aliases | Alternative names/spellings |
| Tax IDs | EIN, VAT numbers, etc. |
| Domains | Email domains (e.g., `acme.com`) |
| Country Code | For bank holiday lookup (ISO 3166-1 alpha-2) |
| Payment Terms | Default days until payment due |

### Processing Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Invoice Confidence | 0.7 | Minimum score to classify as invoice |
| Company Match | 0.8 | Minimum score for company matching |
| Max OCR Pages | 3 | Pages to scan for text extraction |
| Debounce Interval | 3s | Wait time after file event |

## Invoice Generation System

### Templates

Templates define recurring invoices:

- **Client**: Associated company from your configuration
- **Line Items**: Description, quantity, unit price, unit type
- **Currency**: Supports USD, EUR, GBP, CHF, and 13 other currencies
- **Billing Day**: Day of month to generate (1-28)
- **Payment Terms**: Net days until payment due
- **Sender/Recipient**: Full contact details for both parties
- **Notes & Terms**: Custom text appearing on invoices

### Draft Workflow

1. **Pending** - Generated draft awaiting review
2. **Approved** - Reviewed and ready to send
3. **Sent** - Marked as delivered to client
4. **Cancelled** - Discarded draft

### Billing Day & Due Date Calculation

When generating an invoice on billing day:

1. **Find next month's billing day** - e.g., billing day 15 generates an invoice due the 15th of next month
2. **Adjust for non-working days** - If the billing day falls on a weekend or bank holiday, shift to the previous working day
3. **Calculate due date** - Subtract 1 working day from the adjusted billing day

This ensures payment arrives before the billing day (useful for salary payments or other time-sensitive transfers).

### Bank Holiday Integration

Invoice Filer fetches bank holiday data from the [Nager.Date API](https://date.nager.at/) for:

- **Sender's country** - Your location
- **Recipient's country** - Client's location

Both countries' holidays are considered when calculating working days. Holiday data is cached to minimize API calls.

**Supported countries include**: US, GB, DE, FR, CA, AU, NL, NO, CH, JP, SG, and more.

## Data Storage

| Type | Location |
|------|----------|
| Configuration | `~/Library/Application Support/InvoiceFiler/config.json` |
| Templates | `~/Library/Application Support/InvoiceFiler/Invoices/templates.json` |
| Drafts | `~/Library/Application Support/InvoiceFiler/Invoices/drafts.json` |
| Logs | `~/Library/Logs/InvoiceFiler/moves.jsonl` |
| Holiday Cache | `~/Library/Application Support/InvoiceFiler/Cache/bank_holidays.json` |

## Permissions

Invoice Filer requires **Full Disk Access** to monitor directories outside the app sandbox. Grant this in:

System Settings > Privacy & Security > Full Disk Access

## Requirements

- macOS 13.0 (Ventura) or later
- Full Disk Access permission (for directory monitoring)

## Building

Open `InvoiceFiler.xcodeproj` in Xcode and build. No external dependencies required.

## License

See [LICENSE](LICENSE) file.
