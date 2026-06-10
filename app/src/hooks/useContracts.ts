"use client";

import { useMemo } from "react";
import { type Address } from "viem";
import {
  SDIEM_V2_ADDRESS,
  CSDIEM_V2_ADDRESS,
} from "@/config/contracts";

// Lightweight address resolution. ABIs are imported directly in each hook
// because wagmi's type inference doesn't handle ABI unions cleanly.
export type ActiveContracts = {
  sdiem: Address;
  csdiem: Address;
  isV2: boolean;
};

export function useContracts(): ActiveContracts {
  return useMemo(
    () => ({
      sdiem: SDIEM_V2_ADDRESS,
      csdiem: CSDIEM_V2_ADDRESS,
      isV2: true,
    }),
    []
  );
}
