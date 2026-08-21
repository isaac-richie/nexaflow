/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  webpack: (config) => {
    // `wagmi/connectors` is a barrel: importing `injected` from it also drags in
    // Coinbase's Base Account connector, which optionally requires the x402
    // payment SDK. We never construct that connector, but webpack still has to
    // resolve the imports, so the build fails on packages we do not want.
    //
    // Aliasing them to false satisfies the resolver without installing SDKs the
    // app has no use for. If a Base/Coinbase connector is ever added, drop these
    // and install the real dependencies instead.
    config.resolve.alias = {
      ...config.resolve.alias,
      "@x402/core/client": false,
      "@x402/evm": false,
      "@x402/evm/exact/client": false,
      "@x402/evm/upto/client": false,
      "@x402/svm/exact/client": false,
      // MetaMask's SDK ships a React Native storage path it only uses on
      // mobile-native. Irrelevant in a browser build.
      "@react-native-async-storage/async-storage": false,

      // Privy bundles optional product surfaces we do not enable: the Stripe
      // fiat on-ramp and a Farcaster/Solana mini-app connector. Webpack still
      // has to resolve their imports even though the code paths are never
      // reached, so the build fails on SDKs this app has no use for.
      // If fiat on-ramp or Farcaster login is ever turned on in the Privy
      // config, drop the matching line and install the real dependency.
      "@stripe/crypto": false,
      "@farcaster/mini-app-solana": false,
    };

    // Optional peer deps of WalletConnect's logger and storage layers. Marking
    // them external keeps them out of the client bundle.
    config.externals.push("pino-pretty", "lokijs", "encoding");

    // Privy imports Viem's chain catalog, and recent Viem versions include
    // Tempo support through ox. Tempo's optional virtual master pool uses a
    // dynamic require expression that webpack warns about even though this app
    // only enables BSC chains. Keep the build output clean without muting other
    // warnings.
    config.ignoreWarnings = [
      ...(config.ignoreWarnings ?? []),
      {
        module: /node_modules\/ox\/_esm\/tempo\/internal\/virtualMasterPool\.js/,
        message: /Critical dependency: the request of a dependency is an expression/,
      },
    ];

    return config;
  },
};

export default nextConfig;
