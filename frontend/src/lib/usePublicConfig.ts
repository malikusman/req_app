import { useEffect, useState } from 'react';
import { api } from './api';

type PublicConfig = { companySignupEnabled: boolean };

// Fetched once per page load and shared: every marketing component that asks
// gets the same answer without its own request.
let pending: Promise<PublicConfig> | null = null;

function loadPublicConfig(): Promise<PublicConfig> {
  pending ??= api
    .publicConfig()
    .then((c) => ({ companySignupEnabled: c.company_signup_enabled === true }))
    // If the switch can't be read, behave as if sign-up is off: Mjadi sets up
    // engagements itself, so hiding the link loses nothing.
    .catch(() => ({ companySignupEnabled: false }));
  return pending;
}

/** Switches the public site needs. `null` until known. */
export function usePublicConfig(): PublicConfig | null {
  const [config, setConfig] = useState<PublicConfig | null>(null);
  useEffect(() => {
    let live = true;
    loadPublicConfig().then((c) => live && setConfig(c));
    return () => {
      live = false;
    };
  }, []);
  return config;
}
