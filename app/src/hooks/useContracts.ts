"use client";

import { useMemo } from "react";
import { type Address } from "viem";
import {
  SDIEM_ADDRESS,
  SDIEM_V2_ADDRESS,
  CSDIEM_ADDRESS,
  CSDIEM_V2_ADDRESS,
} from "@/config/contracts";
import { useVersion } from "./useVersion";

// Lightweight version-aware address resolution. ABIs are imported directly
// in each hook (wagmi's type inference doesn't handle ABI unions), so this
// hook only exposes the addresses + a boolean flag.
export type ActiveContracts = {
  sdiem: Address;
  csdiem: Address;
  isV2: boolean;
};

export function useContracts(): ActiveContracts {
  const { version } = useVersion();
  return useMemo(() => {
    if (version === "v2") {
      return {
        sdiem: SDIEM_V2_ADDRESS,
        csdiem: CSDIEM_V2_ADDRESS,
        isV2: true,
      };
    }
    return {
      sdiem: SDIEM_ADDRESS,
      csdiem: CSDIEM_ADDRESS,
      isV2: false,
    };
  }, [version]);
}
