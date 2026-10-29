import type { ReportResponse } from '../../pages/reports/types'

export type MoneySeries = { label: string; exact: string | null; accent?: boolean }
export type ChartDatum = MoneySeries & { geometry: number }

// Conversion is strictly for SVG coordinates. Never use geometry for totals,
// payments, labels or tooltips; those retain the original decimal string.
export function chartData(series: MoneySeries[]): ChartDatum[] {
  return series.flatMap(row => {
    if (row.exact === null || !/^-?\d+(\.\d+)?$/.test(row.exact)) return []
    const geometry = Number(row.exact)
    return Number.isFinite(geometry) ? [{ ...row, geometry }] : []
  })
}

export function reportSeries(report: ReportResponse): { series: MoneySeries[]; scope: string } {
  const metrics = report.definition.metrics.filter(m => m.kind === 'money')
  if (metrics.length >= 2) return {
    series: metrics.map(m => ({ label: m.label, exact: typeof report.summary[m.key] === 'string' ? report.summary[m.key] as string : null })),
    scope: `Complete period · ${report.filter.from} — ${report.filter.to} · ${report.total} matching records`,
  }
  const money = report.definition.columns.find(c => c.kind === 'money')
  if (!money) return { series: [], scope: 'Comparable MMK amounts are unavailable for this report. Quantities with different units are not combined.' }
  const label = report.definition.columns.find(c => c.kind === 'text')
  return {
    series: report.rows.slice(0, 8).map((row, index) => ({ label: `${index + 1}. ${label ? row[label.key] || 'Record' : 'Record'}`, exact: row[money.key] ?? null })),
    scope: `${money.label} · first ${Math.min(8, report.rows.length)} records on page ${report.filter.page} · not a full-period total or trend`,
  }
}
