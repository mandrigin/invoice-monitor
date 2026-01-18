# Invoice Filer User Guide

This guide covers how to use Invoice Filer's invoice generation features.

## Table of Contents

1. [Setting Up Invoice Templates](#setting-up-invoice-templates)
2. [Understanding Billing Day & Due Date Calculation](#understanding-billing-day--due-date-calculation)
3. [How Bank Holidays Affect Scheduling](#how-bank-holidays-affect-scheduling)
4. [Exporting Invoices to PDF](#exporting-invoices-to-pdf)
5. [Deleting and Discarding Drafts](#deleting-and-discarding-drafts)

---

## Setting Up Invoice Templates

Templates are the foundation for generating recurring invoices. Each template defines what appears on the invoice and when it should be generated.

### Creating a New Template

1. Click the Invoice Filer icon in the menu bar
2. Select **Invoice Management...**
3. Go to the **Templates** tab
4. Click **New Template**

### Template Fields

#### Basic Information

| Field | Description |
|-------|-------------|
| **Template Name** | A descriptive name (e.g., "Monthly Retainer - Acme Corp") |
| **Client** | Select from your configured companies |
| **Currency** | The invoice currency (USD, EUR, GBP, etc.) |
| **Active** | Whether this template generates invoices automatically |
| **Billing Day** | Day of month to generate (1-28) |
| **Payment Terms** | Net days until payment is due |

#### Line Items

Add the services or products you're billing for:

1. Click **Add Line Item**
2. Enter:
   - **Description**: What you're billing for (e.g., "Software Development Services")
   - **Quantity**: How many units
   - **Unit** (optional): Type of unit (hours, days, units)
   - **Unit Price**: Price per unit
3. Click **Save**

You can add multiple line items. The subtotal updates automatically.

#### Sender Details (Your Information)

Fill in your business details:
- Name and company
- Address (line 1, line 2, city, state, postal code)
- Country (important for bank holiday calculation)
- Email and phone
- Tax ID (VAT, EIN, etc.)

#### Recipient Details (Client Information)

Fill in your client's details:
- Contact name and company
- Full address
- Country (important for bank holiday calculation)
- Email

#### Additional Details

- **Notes**: Text that appears on the invoice (e.g., project references, thank you message)
- **Terms**: Payment terms and conditions

### Saving the Template

Click **Save** to create the template. If **Active** is enabled and **Invoice Scheduling** is turned on in settings, the template will automatically generate drafts on the billing day each month.

---

## Understanding Billing Day & Due Date Calculation

Invoice Filer uses a smart system to calculate when invoices are generated and when they're due.

### The Billing Day

The **Billing Day** is the day of the month when a draft invoice is generated. You can set this from 1 to 28 (to avoid issues with shorter months).

**Example**: If your billing day is 15, the app will generate a draft invoice on the 15th of each month.

### How Due Dates Are Calculated

The due date calculation ensures payment arrives before the actual billing day, which is important for time-sensitive payments like salaries. Here's the process:

1. **Start with next month's billing day**
   - If billing day is 15 and today is January 15th, the target is February 15th

2. **Adjust for non-working days**
   - If February 15th is a Saturday, Sunday, or bank holiday, move to the previous working day
   - Example: If Feb 15 is Saturday → adjusted to Feb 14 (Friday)

3. **Calculate the due date**
   - Subtract 1 working day from the adjusted billing day
   - Example: Feb 14 (Friday) minus 1 working day → Feb 13 (Thursday) = **Due Date**

### Why This Matters

This calculation ensures:
- Your invoice is generated on a predictable day
- The due date falls on a working day
- Payment has time to clear before the billing day
- Bank holidays in both your country and your client's country are respected

### Payment Terms Display

The invoice shows payment terms (e.g., "Net 30") which represents the days between the issue date and due date. This is calculated automatically based on the due date.

---

## How Bank Holidays Affect Scheduling

Invoice Filer integrates with the Nager.Date API to fetch bank holiday data for accurate working day calculations.

### Which Holidays Are Considered

When calculating working days, the app checks holidays in **both**:
- Your country (sender's country in the template)
- Your client's country (recipient's country in the template)

If a date is a holiday in either country, it's not considered a working day.

### Setting Your Country

1. Open **Invoice Management...**
2. Go to the **Settings** tab
3. Select **Your Country** from the dropdown

This is your default sender country. You can override it per-template in the sender details.

### Setting Client Country

In each template's **Recipient Details** section, set the client's country. This ensures their local holidays are considered.

### Supported Countries

The app supports bank holidays for many countries including:
- United States (US)
- United Kingdom (GB)
- Germany (DE)
- France (FR)
- Canada (CA)
- Australia (AU)
- Netherlands (NL)
- Norway (NO)
- Switzerland (CH)
- Japan (JP)
- Singapore (SG)

### Holiday Data Caching

Holiday data is cached locally to minimize API calls. The cache is stored at:
```
~/Library/Application Support/InvoiceFiler/Cache/bank_holidays.json
```

### Fallback Behavior

If the holiday API is unavailable, the app falls back to weekend-only detection (Saturday and Sunday are skipped, but bank holidays won't be considered).

---

## Exporting Invoices to PDF

You can export any draft invoice to a PDF file.

### From the Draft Editor

1. Open **Invoice Management...**
2. Go to the **Drafts** tab
3. Click on a draft to open the editor
4. Click **Export PDF** in the preview panel

### Where PDFs Are Saved

PDFs are saved to an organized folder structure:

1. **If a destination root is configured** (in Preferences):
   ```
   [Destination Root]/YYYY-MM Invoices/INVOICE-NUMBER.pdf
   ```

2. **Otherwise**, PDFs go to your Documents folder:
   ```
   ~/Documents/YYYY-MM Invoices/INVOICE-NUMBER.pdf
   ```

The folder is named based on the invoice issue date (e.g., "2026-01 Invoices").

### After Export

After exporting, the app automatically:
1. Creates the destination folder if it doesn't exist
2. Saves the PDF
3. Opens Finder and highlights the new PDF

### Filename Conflicts

If a file with the same name already exists, the app appends a number:
- `ACME-202601-001.pdf`
- `ACME-202601-001-1.pdf`
- `ACME-202601-001-2.pdf`

---

## Deleting and Discarding Drafts

You can remove drafts you no longer need in two ways:

### Discarding a Draft (From Editor)

Use this when editing a draft you want to throw away:

1. Open the draft in the editor (click on it in the Drafts list)
2. Click **Discard Draft**
3. Confirm in the dialog that appears

**Note**: This completely removes the draft. It cannot be undone.

### Deleting a Draft (From List)

Use this for quick deletion without opening the editor:

1. In the **Drafts** tab, right-click on a draft
2. Select **Delete**
3. Confirm in the dialog that appears

### Cancelling vs. Deleting

There's also a **Cancel Draft** option for pending drafts:

- **Cancel**: Changes the status to "Cancelled" but keeps the draft in your history
- **Delete**: Permanently removes the draft from the system

Use Cancel when you want to keep a record; use Delete when you want it gone completely.

### Bulk Management

Currently, drafts must be deleted one at a time. For bulk cleanup:
1. Filter by status using the segmented control (All / Pending / Approved / Sent)
2. Delete unwanted drafts individually

---

## Quick Reference

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Invoice Management | ⌘I |
| Open Preferences | ⌘, |
| View Log | ⌘L |
| Quit | ⌘Q |

### Invoice Statuses

| Status | Meaning |
|--------|---------|
| Pending | Draft generated, awaiting review |
| Approved | Reviewed, ready to send |
| Sent | Marked as delivered |
| Cancelled | Discarded but kept in history |

### Invoice Number Format

Generated invoices use the format:
```
[PREFIX]-YYYYMM-NNN
```

Where:
- **PREFIX**: First 4 characters of client name (uppercase)
- **YYYYMM**: Year and month
- **NNN**: Sequence number (001, 002, etc.)

Example: `ACME-202601-001`

---

## Troubleshooting

### Drafts Not Generating Automatically

Check that:
1. **Invoice Scheduling** is enabled (Settings tab)
2. The template is marked **Active**
3. Today matches the billing day (adjusted for holidays)
4. No draft was already generated this month for the template

### Wrong Due Date

Verify:
1. Sender country is set correctly
2. Recipient country is set correctly
3. Bank holiday data is up to date (try clearing cache)

### PDF Export Fails

Ensure:
1. The destination folder is writable
2. You have disk permissions (Full Disk Access if needed)
3. The filename doesn't contain invalid characters

For additional help, check the log viewer (⌘L) for error messages.
