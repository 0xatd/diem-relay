import { createConfig, http } from "wagmi";
import { base } from "wagmi/chains";
import { injected, coinbaseWallet } from "wagmi/connectors";

const baseRpcUrl =
  process.env.NEXT_PUBLIC_ALCHEMY_URL ??
  "https://mainnet.base.org";

export const config = createConfig({
  chains: [base],
  connectors: [
    injected(),
    coinbaseWallet({ appName: "DIEM Relay" }),
  ],
  transports: {
    [base.id]: http(baseRpcUrl),
  },
  ssr: true,
});
