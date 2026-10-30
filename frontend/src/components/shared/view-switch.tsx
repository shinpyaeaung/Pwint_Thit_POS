type Choice = { value: string; label: string }
// These controls select views/filters, rather than implementing ARIA tab panels.
export function ViewSwitch({ label, value, choices, onChange }: { label: string; value: string; choices: readonly Choice[]; onChange: (value: string) => void }) {
  return <div role="group" aria-label={label} className="tab-strip">{choices.map(choice=><button type="button" key={choice.value} className="tab-button" aria-pressed={value===choice.value} onClick={()=>onChange(choice.value)}>{choice.label}</button>)}</div>
}
