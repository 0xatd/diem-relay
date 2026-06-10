"use client";

import { RainbowKitProvider, darkTheme, lightTheme } from "@rainbow-me/rainbowkit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import { config } from "@/config/wagmi";
import { useEffect, useState, type ReactNode } from "react";

import "@rainbow-me/rainbowkit/styles.css";

export function Providers({ children }: { children: ReactNode }) {
  const [themeMode, setThemeMode] = useState<"light" | "dark">("light");
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
  const rainbowKitTheme =
    themeMode === "dark"
      ? darkTheme({
          accentColor: "#6f78ff",
          accentColorForeground: "#fff",
          borderRadius: "medium",
        })
      : lightTheme({
          accentColor: "#4a52e0",
          accentColorForeground: "#fff",
          borderRadius: "medium",
        });

  useEffect(() => {
    const syncTheme = () => {
      setThemeMode(document.documentElement.classList.contains("theme-dark") ? "dark" : "light");
    };
    const onThemeChange = (event: Event) => {
      const nextTheme = (event as CustomEvent<"light" | "dark">).detail;
      setThemeMode(nextTheme === "dark" ? "dark" : "light");
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
