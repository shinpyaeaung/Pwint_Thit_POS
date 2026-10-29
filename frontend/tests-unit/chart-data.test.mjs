import { test } from 'node:test'
import assert from 'node:assert/strict'
import { chartData, reportSeries } from '../src/components/charts/chart-data.ts'

test('chart geometry retains exact money strings and signed/zero values',()=>{
 const data=chartData([{label:'Large',exact:'9999999999999999.1234'},{label:'Refund',exact:'-0.1234'},{label:'Zero',exact:'0.0000'},{label:'Unknown',exact:null}])
 assert.equal(data[0].exact,'9999999999999999.1234')
 assert.equal(data[1].geometry,-0.1234)
 assert.equal(data[2].geometry,0)
 assert.equal(data.length,3)
})
test('invalid and non-finite geometry is omitted, not made into zero',()=>{
 assert.deepEqual(chartData(['','NaN','1e10','9'.repeat(400),null].map(exact=>({label:'Invalid',exact}))),[])
})
const report={definition:{metrics:[{key:'net',label:'Net',kind:'money'},{key:'cost',label:'Cost',kind:'money'}],columns:[{key:'name',kind:'text'},{key:'amount',label:'Amount',kind:'money'}]},summary:{net:'9007199254740993.0001',cost:null},filter:{from:'2026-01-01',to:'2026-01-31',page:2},rows:[{name:'Invoice',amount:'9.5000'}],total:100}
test('report comparisons use full summaries, preserving unknown costs',()=>{
 const result=reportSeries(report)
 assert.equal(result.series[0].exact,'9007199254740993.0001')
 assert.equal(result.series[1].exact,null)
 assert.match(result.scope,/100 matching records/)
})
test('record charts disclose page scope and never aggregate mixed units',()=>{
 const result=reportSeries({...report,definition:{...report.definition,metrics:[]}})
 assert.equal(result.series[0].exact,'9.5000')
 assert.match(result.scope,/page 2 · not a full-period/)
 assert.deepEqual(reportSeries({...report,definition:{metrics:[],columns:[{kind:'decimal'}]}}).series,[])
})
