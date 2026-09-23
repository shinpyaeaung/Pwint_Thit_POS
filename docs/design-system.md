# Phase 4 — Frontend design system

The application stays light-only. Primary red `#ba0d0d` is reserved for actions and active navigation. Accent yellow `#f7a712` supports pending/warning states. Background `#f8f8f8`, white panels, neutral text, soft borders, Inter, compact spacing, and tabular figures keep operational screens easy to scan.

The authenticated `/design-system` page is a component reference requiring `settings.manage`. All records and financial values there are explicitly labeled previews. It does not write business records. Existing workspace, users, and permissions screens use the shared components; future business modules should extend these rather than create competing page patterns.

## Component map

Import shared components from `@/components/shared` and layout components from `@/components/layout/<name>`.

| Component | Responsibility and important props |
| --- | --- |
| AppShell | Sidebar, sticky header, skip link, main landmark, responsive drawer; `user`, `onLogout`, `signingOut` |
| Sidebar | Permission-filtered navigation, current-page indication, distribution identity; only implemented routes are linked |
| Header | Current user, role, mobile navigation, sign-out |
| PageHeader | `eyebrow`, `title`, `description`, optional `actions` |
| StatCard | `label`, `value`, `detail`, optional icon; callers format actual values |
| DataTable | Generic `rows`, typed `columns`, stable `rowKey`, accessible `caption`; optional comparator per column, pagination, loading/error/retry/empty states |
| SearchInput | Labeled controlled search, `value`, `onValueChange`, clear action |
| FilterBar | Composes search and labeled filters; optional `summary`, `onReset` |
| Modal | Controlled `open`, `onOpenChange`, title, description, children, footer, `busy` |
| Drawer | Same contract as Modal, with `side` left/right |
| ConfirmDialog | Explicit cancel/confirm; `onConfirm`, `confirmLabel`, optional error, busy/destructive states |
| FormField | Label, hint, error, required indicator; child render function receives ID and accessibility attributes |
| CurrencyInput | Controlled decimal **string**; defaults to MMK, 16 integer digits and 4 decimal places |
| QuantityInput | Controlled decimal **string**; defaults to 14 integer digits and 6 decimal places, customizable unit |
| StatusBadge | Text plus visual tone: neutral, success, warning, danger, info; color is never the sole status indicator |
| EmptyState | Title, description, optional action |
| LoadingState | Polite status text and reduced-motion-aware skeleton rows |
| PermissionGuard | Conditional presentation using current-user permissions; optional fallback; never replaces backend checks |

## Forms and exact numbers

```tsx
const [amount, setAmount] = useState('')
<FormField label="Purchase amount (MMK)" required hint="Up to 4 decimal places.">
  {control => <CurrencyInput {...control} value={amount} onValueChange={setAmount} />}
</FormField>
```

Inputs retain decimal strings, including trailing zeros. They do not call Number/parseFloat, perform exchange conversions, round financial values, or silently discard invalid keystrokes. HTML pattern validation and aria-invalid flag unsupported formats (exponents, commas, excessive precision, negatives by default). An enclosing form must validate before submitting; future APIs must validate independently. `scale`, `integerDigits`, and `allowNegative` may be configured for domain-specific fields. Match these to the database column. Preserve strings in JSON requests.

DataTable sorting is opt-in through typed comparator functions. Do not sort money by converting it to JavaScript Number; use decimal-safe comparisons when business data arrives. The current table paginates already-loaded records on the client. Large datasets will need explicit server pagination/filtering in their own vertical slices. Search/filter changes should reset the table using a key as shown in Users and Permissions.

## Accessibility and motion

The overlay implementation uses the Radix primitive behind the [shadcn dialog pattern](https://ui.shadcn.com/docs/components/radix/dialog), with shared brand styling and existing shadcn buttons. It provides modal focus containment, background inertness, Escape dismissal, title/description association, focus restoration, scrolling content, and fixed action footers. Busy mutations prevent dismissal and duplicate confirmation. Confirmation defaults to a non-destructive close control rather than an automatic confirm action.

Framer Motion is limited to a 150ms overlay entrance with a small displacement. Reduced motion removes that entrance and disables CSS transitions/skeleton animation. No animated financial totals or decorative row animations are used.

Use `FormField` with its supplied control props, meaningful button names, text-bearing badges, and table captions. The desktop sidebar becomes a modal navigation drawer on mobile. Wide tables scroll inside their own labeled, keyboard-focusable region.

## Scope

No new business APIs, financial rules, database migrations, or extra roles were introduced. Go permission enforcement remains unchanged. User creation and staff permission editing still call the Phase 3 API; permission replacement now includes a confirmation step. Navigation includes only implemented pages. The source-to-shelf journey is explanatory, not live stock or shipment data.
