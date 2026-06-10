"use client";

import { RainbowKitProvider, darkTheme, lightTheme } from "@rainbow-me/rainbowkit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import { config } from "@/config/wagmi";
import { useEffect, useState, type ReactNode } from "react";

import "@rainbow-me/rainbowkit/styles.css";

export function Providers({ children }: { children: ReactNode }) {
  const [themeMode, setThemeMode] = useState<"dark" | "light">("dark");
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 10_000,
            refetchInterval: 15_000,
          },
        },
      })
  );
  const rainbowKitTheme = themeMode === "dark"
    ? darkTheme({
        accentColor: "#f5a623",
        accentColorForeground: "#000",
        borderRadius: "medium",
      })
    : lightTheme({
        accentColor: "#f5a623",
        accentColorForeground: "#000",
        borderRadius: "medium",
      });

  useEffect(() => {
    const syncTheme = () => {
      setThemeMode(document.documentElement.classList.contains("light") ? "light" : "dark");
    };
    const onThemeChange = (event: Event) => {
      const nextTheme = (event as CustomEvent<"dark" | "light">).detail;
      setThemeMode(nextTheme === "light" ? "light" : "dark");
    };

    syncTheme();
    window.addEventListener("diem-theme-change", onThemeChange);
    return () => window.removeEventListener("diem-theme-change", onThemeChange);
  }, []);

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider
          theme={rainbowKitTheme}
        >
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
