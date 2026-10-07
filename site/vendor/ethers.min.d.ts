// Type boundary for the unchanged vendored ethers browser runtime. Contracts remain ABI-dynamic.
  export const BrowserProvider: any, JsonRpcProvider: any, FetchRequest: any, Contract: any;
  export const ZeroAddress: string, ZeroHash: string;
  export const parseUnits: (value: string, decimals?: number) => bigint;
  export const formatUnits: (value: bigint | string | number, decimals?: number) => string;
  export const randomBytes: (length: number) => Uint8Array;
  export const hexlify: (value: Uint8Array) => string;
  export const getAddress: (value: string) => string;
  export const AbiCoder: any;
  export const keccak256: (data: string) => string;
