export type ReportColumn = { key: string; label: string; kind: 'text' | 'money' | 'decimal' | 'date' | 'datetime' }
export type ReportDefinition = { id: string; title: string; description: string; columns: ReportColumn[]; metrics: ReportColumn[] }
export type ReportFilter = { period: string; from?: string; to?: string; page: number; page_size: number }
export type ReportRow = Record<string, string | null>
export type ReportResponse = {
  definition: ReportDefinition
  filter: Required<ReportFilter>
  total: number
  summary: Record<string, string | number | null>
  rows: ReportRow[]
}
