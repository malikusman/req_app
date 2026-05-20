export function SocialProofSection() {
  const logos = ['Acme Corp', 'Northwind', 'Globex', 'Initech', 'Umbrella'];
  const stats = [
    { value: '40+', label: 'Companies analyzed' },
    { value: '12k+', label: 'Workflows discovered' },
    { value: '2.4M', label: 'Hours surfaced for optimization' },
  ];

  return (
    <section className="bg-surface px-6 py-20 md:px-12">
      <div className="mx-auto max-w-6xl text-center">
        <p className="text-label-caps text-text-secondary">Trusted by transformation teams</p>
        <div className="mt-8 flex flex-wrap items-center justify-center gap-8 opacity-60">
          {logos.map((name) => (
            <span key={name} className="text-lg font-semibold text-text-secondary">
              {name}
            </span>
          ))}
        </div>
        <blockquote className="mx-auto mt-16 max-w-3xl">
          <p className="font-display text-2xl italic leading-relaxed text-text-primary md:text-3xl">
            &ldquo;We finally had a shared picture of how work actually flows — not how the org chart says it
            should.&rdquo;
          </p>
          <footer className="mt-4 text-sm text-text-secondary">
            — VP Operations, Fortune 500 manufacturer
          </footer>
        </blockquote>
        <div className="mt-16 grid grid-cols-3 gap-8">
          {stats.map((stat) => (
            <div key={stat.label} className="border-t border-border pt-8">
              <div className="mx-auto mb-4 h-0 w-12 border-t-2 border-accent" aria-hidden />
              <p className="font-display text-6xl font-bold text-accent">{stat.value}</p>
              <p className="mt-2 text-sm text-text-secondary">{stat.label}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
