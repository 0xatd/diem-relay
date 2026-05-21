"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { DEFAULT_VERSION } from "@/config/contracts";

export type Version = "v1" | "v2";

type Ctx = {
  version: Version;
  setVersion: (v: Version) => void;
};

const VersionContext = createContext<Ctx | null>(null);

const STORAGE_KEY = "diem-relay-version";

function readStoredVersion(): Version {
  if (typeof window === "undefined") return DEFAULT_VERSION;
  const stored = window.localStorage.getItem(STORAGE_KEY);
  return stored === "v1" || stored === "v2" ? stored : DEFAULT_VERSION;
}

export function VersionProvider({ children }: { children: ReactNode }) {
  // SSR-safe: start with the static default; hydrate from localStorage in an
  // effect to avoid hydration mismatches.
  const [version, setVersionState] = useState<Version>(DEFAULT_VERSION);

  useEffect(() => {
    setVersionState(readStoredVersion());
  }, []);

  const setVersion = useCallback((v: Version) => {
    setVersionState(v);
    if (typeof window !== "undefined") {
      window.localStorage.setItem(STORAGE_KEY, v);
    }
  }, []);

  return (
    <VersionContext.Provider value={{ version, setVersion }}>
      {children}
    </VersionContext.Provider>
  );
}

export function useVersion(): Ctx {
  const ctx = useContext(VersionContext);
  if (!ctx) throw new Error("useVersion must be used within VersionProvider");
  return ctx;
}
