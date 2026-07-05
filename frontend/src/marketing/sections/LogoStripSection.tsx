import { LogoMarquee } from '../../components/motion';
import { marketingContent } from '../content';

export function LogoStripSection() {
  const { logos } = marketingContent;

  return (
    <section className="border-y border-marketing-border bg-marketing-surface px-6 py-10 md:px-12">
      <div className="mx-auto max-w-6xl text-center">
        <p className="text-label-caps text-marketing-muted">{logos.eyebrow}</p>
        <div className="mt-6 [&_span]:text-marketing-muted">
          <LogoMarquee items={[...logos.industries]} />
        </div>
      </div>
    </section>
  );
}
