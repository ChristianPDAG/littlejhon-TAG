import { useSyncExternalStore } from "react";

const emptySubscribe = () => () => {};

/**
 * Returns `false` during server-side rendering and the first client render,
 * then `true` once the component has hydrated on the client.
 *
 * Use this to gate wallet-dependent (or otherwise client-only) UI so the
 * server HTML matches the first client render and React does not report a
 * hydration mismatch. Implemented with `useSyncExternalStore` so it does not
 * call `setState` inside an effect.
 */
export function useHydrated(): boolean {
  return useSyncExternalStore(
    emptySubscribe,
    () => true,
    () => false,
  );
}
