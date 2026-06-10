"use client";

import { useEffect, useMemo, useState } from 'react';
import {
  useAccount,
  useChainId,
  useReadContracts,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from 'wagmi';
import { base } from 'wagmi/chains';
import { formatUnits, parseUnits, type Address } from 'viem';
import { Header } from '@/components/Header';
import { csDiemV2Abi, erc20Abi, sDiemV2Abi } from '@/config/abis';
import { CSDIEM_V2_ADDRESS, DIEM_TOKEN, SDIEM_V2_ADDRESS } from '@/config/contracts';
import { CONTRACTS_SECTION_URL, GITHUB_URL } from '@/config/protocol-links';


type SupplyMode = 'liquid' | 'convert' | 'direct';
type ActionMode = 'supply' | 'withdraw';
type WithdrawMode = 'liquid' | 'unwrap' | 'exit';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as Address;
const DAY_SECONDS = 86_400n;

function formatToken(value: bigint, decimals = 18, maxFraction = 4) {
  const numeric = Number(formatUnits(value, decimals));
  if (!Number.isFinite(numeric)) return '0';
  return numeric.toLocaleString(undefined, {
    maximumFractionDigits: numeric >= 100 ? 2 : maxFraction,
  });
}

function formatUsd(value: bigint, maxFraction = 2) {
  const numeric = Number(formatUnits(value, 6));
  if (!Number.isFinite(numeric)) return '$0.00';
  return numeric.toLocaleString(undefined, {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: maxFraction,
  });
}

function formatApy(usdcPerDiemDay: bigint) {
  const annualPercent = Number(formatUnits(usdcPerDiemDay, 6)) * 365 * 100;
  if (!Number.isFinite(annualPercent) || annualPercent <= 0) return 'APY pending';
  return `${annualPercent.toLocaleString(undefined, {
    maximumFractionDigits: annualPercent >= 100 ? 0 : 2,
  })}%`;
}

function shortAddress(address: Address) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function parseDiemAmount(value: string) {
  try {
    return value.trim() ? parseUnits(value, 18) : 0n;
  } catch {
    return 0n;
  }
}

function secondsUntil(timestamp: bigint) {
  const now = BigInt(Math.floor(Date.now() / 1000));
  return timestamp > now ? timestamp - now : 0n;
}

function formatDuration(seconds: bigint) {
  const total = Number(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours <= 0) return `${minutes}m`;
  return `${hours}h ${minutes}m`;
}

export default function PoolPage() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain, isPending: isSwitching } = useSwitchChain();
  const [actionMode, setActionMode] = useState<ActionMode>('supply');
  const [mode, setMode] = useState<SupplyMode>('liquid');
  const [withdrawMode, setWithdrawMode] = useState<WithdrawMode>('liquid');
  const [depositAmount, setDepositAmount] = useState('');
  const [redeemAmount, setRedeemAmount] = useState('');
  const [withdrawAmount, setWithdrawAmount] = useState('');

  const account = address ?? ZERO_ADDRESS;
  const diem = DIEM_TOKEN as Address;
  const sdiem = SDIEM_V2_ADDRESS as Address;
  const csdiem = CSDIEM_V2_ADDRESS as Address;
  const spender = mode === 'liquid' ? sdiem : csdiem;
  const parsedDeposit = parseDiemAmount(depositAmount);
  const parsedRedeem = parseDiemAmount(redeemAmount);
  const parsedWithdraw = parseDiemAmount(withdrawAmount);
  const isBase = chainId === base.id;

  const reads = useReadContracts({
    contracts: [
      { address: diem, abi: erc20Abi, functionName: 'balanceOf', args: [account] },
      { address: diem, abi: erc20Abi, functionName: 'allowance', args: [account, csdiem] },
      { address: diem, abi: erc20Abi, functionName: 'allowance', args: [account, sdiem] },
      { address: sdiem, abi: sDiemV2Abi, functionName: 'balanceOf', args: [account] },
      { address: sdiem, abi: sDiemV2Abi, functionName: 'earned', args: [account] },
      { address: sdiem, abi: sDiemV2Abi, functionName: 'withdrawalRequests', args: [account] },
      { address: sdiem, abi: sDiemV2Abi, functionName: 'canCompleteWithdraw', args: [account] },
      { address: sdiem, abi: sDiemV2Abi, functionName: 'totalStaked' },
      { address: sdiem, abi: sDiemV2Abi, functionName: 'rewardRate' },
      { address: sdiem, abi: sDiemV2Abi, functionName: 'periodFinish' },
      { address: sdiem, abi: sDiemV2Abi, functionName: 'paused' },
      { address: csdiem, abi: csDiemV2Abi, functionName: 'totalAssets' },
      { address: csdiem, abi: csDiemV2Abi, functionName: 'totalSupply' },
      { address: csdiem, abi: csDiemV2Abi, functionName: 'balanceOf', args: [account] },
      { address: csdiem, abi: csDiemV2Abi, functionName: 'convertToAssets', args: [parseUnits('1', 18)] },
      { address: csdiem, abi: csDiemV2Abi, functionName: 'previewRedeem', args: [parsedRedeem] },
      { address: csdiem, abi: csDiemV2Abi, functionName: 'maxRedeem', args: [account] },
      { address: csdiem, abi: csDiemV2Abi, functionName: 'paused' },
      { address: csdiem, abi: csDiemV2Abi, functionName: 'pendingHarvest' },
      { address: sdiem, abi: erc20Abi, functionName: 'allowance', args: [account, csdiem] },
      { address: csdiem, abi: csDiemV2Abi, functionName: 'previewDeposit', args: [parsedDeposit] },
    ],
    query: { refetchInterval: 20_000 },
  });

  const results = reads.data as Array<{ result?: unknown; status?: string }> | undefined;
  const read = <T,>(index: number, fallback: T): T =>
    results?.[index]?.status === 'success' ? (results[index].result as T) : fallback;

  const diemBalance = read<bigint>(0, 0n);
  const csAllowance = read<bigint>(1, 0n);
  const sAllowance = read<bigint>(2, 0n);
  const sdiemBalance = read<bigint>(3, 0n);
  const pendingUsdc = read<bigint>(4, 0n);
  const withdrawalRequest = read<readonly [bigint, bigint]>(5, [0n, 0n]);
  const canCompleteWithdraw = read<boolean>(6, false);
  const totalStaked = read<bigint>(7, 0n);
  const rewardRate = read<bigint>(8, 0n);
  const periodFinish = read<bigint>(9, 0n);
  const sdiemPaused = read<boolean>(10, false);
  const csTotalAssets = read<bigint>(11, 0n);
  const csTotalSupply = read<bigint>(12, 0n);
  const csBalance = read<bigint>(13, 0n);
  const csSharePrice = read<bigint>(14, parseUnits('1', 18));
  const redeemPreview = read<bigint>(15, 0n);
  const maxRedeem = read<bigint>(16, 0n);
  const csdiemPaused = read<boolean>(17, false);
  const pendingHarvest = read<bigint>(18, 0n);
  const sdiemToCsAllowance = read<bigint>(19, 0n);
  const convertPreview = read<bigint>(20, 0n);
  const withdrawUsesCsdiem = withdrawMode !== 'liquid';
  const withdrawInputAmount = withdrawUsesCsdiem ? redeemAmount : withdrawAmount;
  const parsedWithdrawInput = withdrawUsesCsdiem ? parsedRedeem : parsedWithdraw;
  const withdrawBalance = withdrawUsesCsdiem ? maxRedeem : sdiemBalance;
  const withdrawToken = withdrawUsesCsdiem ? 'csDIEM' : 'sDIEM';
  const depositToken = mode === 'convert' ? 'sDIEM' : 'DIEM';
  const depositBalance = mode === 'convert' ? sdiemBalance : diemBalance;
  const activeAllowance = mode === 'convert' ? sdiemToCsAllowance : mode === 'direct' ? csAllowance : sAllowance;
  const approvalToken = mode === 'convert' ? sdiem : diem;
  const needsApproval = parsedDeposit > 0n && parsedDeposit > activeAllowance;

  const dailyReward = rewardRate * DAY_SECONDS;
  const usdcPerDiemDay = totalStaked > 0n ? (dailyReward * parseUnits('1', 18)) / totalStaked : 0n;
  const rewardStreamActive = dailyReward > 0n && totalStaked > 0n && secondsUntil(periodFinish) > 0n;
  const currentApyLabel = rewardStreamActive ? formatApy(usdcPerDiemDay) : 'APY pending';
  const dailyRewardLabel = dailyReward > 0n ? `${formatUsd(dailyReward)}/day` : 'Not streaming';
  const withdrawalAmount = withdrawalRequest[0] ?? 0n;
  const withdrawalStart = withdrawalRequest[1] ?? 0n;
  const withdrawalReadyAt = withdrawalStart + DAY_SECONDS;
  const withdrawalWait = secondsUntil(withdrawalReadyAt);

  const connectedLabel = useMemo(() => {
    if (!isConnected || !address) return 'Wallet not connected';
    return `${shortAddress(address)} on ${isBase ? 'Base' : 'wrong network'}`;
  }, [address, isBase, isConnected]);

  const { writeContract, data: txHash, isPending: isWriting, error: writeError } = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (receipt.isSuccess) {
      reads.refetch();
    }
  }, [receipt.isSuccess, reads]);

  const isBusy = isWriting || receipt.isLoading || isSwitching;
  const modePaused = mode === 'liquid' ? sdiemPaused : csdiemPaused;
  const disableReason = !isConnected
    ? 'Connect wallet'
    : !isBase
      ? 'Switch to Base'
      : modePaused
        ? mode === 'liquid' ? 'Staking paused' : 'Conversion paused'
        : parsedDeposit <= 0n
          ? 'Enter amount'
          : parsedDeposit > depositBalance
            ? `Insufficient ${depositToken}`
            : '';
  const withdrawDisableReason = !isConnected
    ? 'Connect wallet'
    : !isBase
      ? 'Switch to Base'
      : withdrawUsesCsdiem && csdiemPaused
        ? 'Conversion paused'
      : withdrawMode === 'liquid' && withdrawalAmount > 0n
        ? 'Withdrawal queued'
        : parsedWithdrawInput <= 0n
          ? 'Enter amount'
          : parsedWithdrawInput > withdrawBalance
            ? `Insufficient ${withdrawToken}`
            : '';

  const handlePrimaryAction = () => {
    if (!isConnected) return;
    if (!isBase) {
      switchChain({ chainId: base.id });
      return;
    }
    if (needsApproval) {
      writeContract({
        address: approvalToken,
        abi: erc20Abi,
        functionName: 'approve',
        args: [spender, parsedDeposit],
      });
      return;
    }
    if (mode === 'direct') {
      writeContract({
        address: csdiem,
        abi: csDiemV2Abi,
        functionName: 'depositDIEM',
        args: [parsedDeposit, account],
      });
      return;
    }
    if (mode === 'convert') {
      writeContract({
        address: csdiem,
        abi: csDiemV2Abi,
        functionName: 'deposit',
        args: [parsedDeposit, account],
      });
      return;
    }
    writeContract({
      address: sdiem,
      abi: sDiemV2Abi,
      functionName: 'stake',
      args: [parsedDeposit],
    });
  };

  const handleClaim = () => {
    writeContract({ address: sdiem, abi: sDiemV2Abi, functionName: 'claimReward' });
  };

  const handleRedeem = () => {
    writeContract({
      address: csdiem,
      abi: csDiemV2Abi,
      functionName: 'redeem',
      args: [parsedRedeem, account, account],
    });
  };

  const handleRequestWithdraw = () => {
    writeContract({
      address: sdiem,
      abi: sDiemV2Abi,
      functionName: 'requestWithdraw',
      args: [parsedWithdraw],
    });
  };

  const handleWithdrawAction = () => {
    if (!isConnected) return;
    if (!isBase) {
      switchChain({ chainId: base.id });
      return;
    }
    if (withdrawUsesCsdiem) {
      handleRedeem();
      return;
    }
    handleRequestWithdraw();
  };

  const handleCompleteWithdraw = () => {
    writeContract({ address: sdiem, abi: sDiemV2Abi, functionName: 'completeWithdraw' });
  };

  const handleCancelWithdraw = () => {
    writeContract({ address: sdiem, abi: sDiemV2Abi, functionName: 'cancelWithdraw' });
  };

  return (
    <>
      <Header />
      <div className="pool-page">
      <div className="pool-shell">
        <section className="pool-hero pool-hero-compact">
          <div>
            <div className="pool-kicker">Staking vault - V2</div>
            <h1 className="pool-title">Stake Diem, earn USDC</h1>
            <p className="pool-subtitle">
              Every Diem is a perpetual $1 inference credit. Supply yours to the pool and collect
              USDC each time someone buys a day of compute.
            </p>
          </div>
          <div className="pool-status-card">
            <span>Net APY</span>
            <strong>{currentApyLabel}</strong>
            <small>{sdiemPaused || csdiemPaused ? 'Vault paused' : 'Paid in USDC'}</small>
          </div>
        </section>

        <section className="pool-app-grid">
          <div className="pool-panel pool-primary-panel">
            <div className="pool-action-tabs">
              <button
                className={actionMode === 'supply' ? 'pool-action-tab-active' : ''}
                onClick={() => setActionMode('supply')}
                type="button"
              >
                Supply
              </button>
              <button
                className={actionMode === 'withdraw' ? 'pool-action-tab-active' : ''}
                onClick={() => setActionMode('withdraw')}
                type="button"
              >
                Withdraw
              </button>
            </div>

            {actionMode === 'supply' ? (
              <div className="pool-form pool-form-main">
                <div className="pool-panel-header pool-inline-header">
                  <div>
                    <h2 className="pool-panel-title">Supply DIEM</h2>
                    <p className="pool-panel-copy">
                      Choose liquid sDIEM rewards, convert existing sDIEM to csDIEM, or enter the
                      compounding vault directly from DIEM.
                    </p>
                  </div>
                </div>

                <div className="pool-token-tabs pool-token-tabs-three">
                  <button
                    className={mode === 'liquid' ? 'pool-token-tab-active' : ''}
                    onClick={() => setMode('liquid')}
                    type="button"
                  >
                    <strong>sDIEM</strong>
                    <span>Liquid staking receipt. Stay liquid and claim streamed USDC rewards manually.</span>
                  </button>
                  <button
                    className={mode === 'convert' ? 'pool-token-tab-active' : ''}
                    onClick={() => setMode('convert')}
                    type="button"
                  >
                    <strong>Convert sDIEM</strong>
                    <span>Move existing sDIEM into csDIEM without leaving the staking system.</span>
                  </button>
                  <button
                    className={mode === 'direct' ? 'pool-token-tab-active' : ''}
                    onClick={() => setMode('direct')}
                    type="button"
                  >
                    <strong>Enter csDIEM</strong>
                    <span>Supply DIEM directly into auto-compounding csDIEM.</span>
                  </button>
                </div>

                {!isConnected ? (
                  <div className="pool-connect">Connect a wallet to supply DIEM.</div>
                ) : (
                  <>
                    <div className="pool-input-row pool-input-row-large">
                      <div className="pool-input-meta">
                        <span>Supply amount</span>
                        <span>Wallet: {formatToken(depositBalance)} {depositToken}</span>
                      </div>
                      <div className="pool-input-line">
                        <input
                          className="pool-input"
                          inputMode="decimal"
                          onChange={(event) => setDepositAmount(event.target.value)}
                          placeholder="0.0"
                          value={depositAmount}
                        />
                        <button
                          className="pool-small-button"
                          onClick={() => setDepositAmount(formatUnits(depositBalance, 18))}
                          type="button"
                        >
                          MAX
                        </button>
                        <span className="pool-token">{depositToken}</span>
                      </div>
                    </div>

                    <div className="pool-preview pool-preview-quiet">
                      <div className="pool-preview-row">
                        <span>You receive</span>
                        <strong>
                          {mode === 'liquid'
                            ? 'sDIEM'
                            : mode === 'convert'
                              ? `${formatToken(convertPreview)} csDIEM`
                              : 'csDIEM'}
                        </strong>
                      </div>
                      <div className="pool-preview-row">
                        <span>Rewards</span>
                        <strong>{mode === 'liquid' ? 'Claim USDC manually' : 'Compounds into csDIEM share price'}</strong>
                      </div>
                      <div className="pool-preview-row">
                        <span>Current rate</span>
                        <strong>{dailyRewardLabel}</strong>
                      </div>
                    </div>

                    <button
                      className="pool-action"
                      disabled={isBusy || (!!disableReason && disableReason !== 'Switch to Base') || (isBase && needsApproval && parsedDeposit <= 0n)}
                      onClick={handlePrimaryAction}
                      type="button"
                    >
                      {!isBase && isConnected
                        ? 'Switch to Base'
                        : needsApproval
                          ? `Approve ${depositToken}`
                          : disableReason ||
                            (mode === 'liquid'
                              ? 'Supply DIEM'
                              : mode === 'convert'
                                ? 'Convert to csDIEM'
                                : 'Supply as csDIEM')}
                    </button>
                  </>
                )}
              </div>
            ) : (
              <div className="pool-form pool-form-main">
                <div className="pool-panel-header pool-inline-header">
                  <div>
                    <h2 className="pool-panel-title">Withdraw DIEM</h2>
                    <p className="pool-panel-copy">Pick the exit path. sDIEM queues a DIEM withdrawal; csDIEM converts back to sDIEM first.</p>
                  </div>
                </div>

                <div className="pool-token-tabs pool-token-tabs-three">
                  <button
                    className={withdrawMode === 'liquid' ? 'pool-token-tab-active' : ''}
                    onClick={() => setWithdrawMode('liquid')}
                    type="button"
                  >
                    <strong>sDIEM</strong>
                    <span>Request DIEM withdrawal</span>
                  </button>
                  <button
                    className={withdrawMode === 'unwrap' ? 'pool-token-tab-active' : ''}
                    onClick={() => setWithdrawMode('unwrap')}
                    type="button"
                  >
                    <strong>Convert csDIEM</strong>
                    <span>Move csDIEM back to sDIEM</span>
                  </button>
                  <button
                    className={withdrawMode === 'exit' ? 'pool-token-tab-active' : ''}
                    onClick={() => setWithdrawMode('exit')}
                    type="button"
                  >
                    <strong>Exit csDIEM</strong>
                    <span>Convert, then withdraw DIEM</span>
                  </button>
                </div>

                {!isConnected ? (
                  <div className="pool-connect">Connect a wallet to withdraw DIEM.</div>
                ) : (
                  <>
                    <div className="pool-input-row pool-input-row-large">
                      <div className="pool-input-meta">
                        <span>Withdraw amount</span>
                        <span>Balance: {formatToken(withdrawBalance)} {withdrawToken}</span>
                      </div>
                      <div className="pool-input-line">
                        <input
                          className="pool-input"
                          inputMode="decimal"
                          onChange={(event) =>
                            withdrawUsesCsdiem
                              ? setRedeemAmount(event.target.value)
                              : setWithdrawAmount(event.target.value)
                          }
                          placeholder="0.0"
                          value={withdrawInputAmount}
                        />
                        <button
                          className="pool-small-button"
                          onClick={() =>
                            withdrawUsesCsdiem
                              ? setRedeemAmount(formatUnits(maxRedeem, 18))
                              : setWithdrawAmount(formatUnits(sdiemBalance, 18))
                          }
                          type="button"
                        >
                          MAX
                        </button>
                        <span className="pool-token">{withdrawToken}</span>
                      </div>
                    </div>

                    <div className="pool-preview pool-preview-quiet">
                      <div className="pool-preview-row">
                        <span>You receive</span>
                        <strong>{withdrawUsesCsdiem ? `${formatToken(redeemPreview)} sDIEM` : 'DIEM after cooldown'}</strong>
                      </div>
                      <div className="pool-preview-row">
                        <span>Next step</span>
                        <strong>
                          {withdrawMode === 'exit'
                            ? 'Then request DIEM withdrawal'
                            : withdrawMode === 'unwrap'
                              ? 'Hold sDIEM or withdraw DIEM'
                              : 'Complete after 24h'}
                        </strong>
                      </div>
                      {withdrawalAmount > 0n && (
                        <div className="pool-preview-row">
                          <span>Queued</span>
                          <strong>
                            {formatToken(withdrawalAmount)} DIEM -{' '}
                            {canCompleteWithdraw ? 'ready' : `${formatDuration(withdrawalWait)} left`}
                          </strong>
                        </div>
                      )}
                    </div>

                    <button
                      className="pool-action"
                      disabled={isBusy || (!!withdrawDisableReason && withdrawDisableReason !== 'Switch to Base')}
                      onClick={handleWithdrawAction}
                      type="button"
                    >
                      {!isBase && isConnected
                        ? 'Switch to Base'
                        : withdrawDisableReason ||
                          (withdrawMode === 'exit'
                            ? 'Start exit: convert csDIEM'
                            : withdrawMode === 'unwrap'
                              ? 'Convert to sDIEM'
                              : 'Request withdrawal')}
                    </button>

                    {withdrawalAmount > 0n && (
                      <button
                        className="pool-secondary-action pool-secondary-action-full"
                        disabled={isBusy || !isConnected}
                        onClick={canCompleteWithdraw ? handleCompleteWithdraw : handleCancelWithdraw}
                        type="button"
                      >
                        {canCompleteWithdraw ? 'Complete withdrawal' : 'Cancel queued withdrawal'}
                      </button>
                    )}
                  </>
                )}
              </div>
            )}

            {txHash && (
              <div className="pool-tx pool-tx-main">
                {receipt.isLoading
                  ? 'Transaction submitted. Waiting for confirmation...'
                  : receipt.isSuccess
                    ? 'Transaction confirmed. Balances refreshed.'
                    : `Transaction: ${shortAddress(txHash as Address)}`}
              </div>
            )}
            {writeError && <div className="pool-tx pool-tx-main">Wallet error: {writeError.message}</div>}
          </div>

          <aside className="pool-panel pool-position-panel">
            <div className="pool-panel-header">
              <div>
                <h2 className="pool-panel-title">Position</h2>
                <p className="pool-panel-copy">{connectedLabel}</p>
              </div>
            </div>

            {!isConnected ? (
              <div className="pool-empty-state pool-empty-state-large">
                Connect a wallet to see supplied DIEM, claimable rewards, and withdrawal status.
              </div>
            ) : (
              <>
                {withdrawalAmount > 0n && (
                  <div className="pool-pending-card">
                    <div>
                      <span>Pending withdrawal</span>
                      <strong>{formatToken(withdrawalAmount)} DIEM</strong>
                      <small>{canCompleteWithdraw ? 'Ready to complete' : `${formatDuration(withdrawalWait)} remaining`}</small>
                    </div>
                    <button
                      className="pool-secondary-action"
                      disabled={isBusy}
                      onClick={canCompleteWithdraw ? handleCompleteWithdraw : handleCancelWithdraw}
                      type="button"
                    >
                      {canCompleteWithdraw ? 'Complete' : 'Cancel'}
                    </button>
                  </div>
                )}

                <div className="pool-balance-grid">
                  <div>
                    <span>DIEM</span>
                    <strong>{formatToken(diemBalance)}</strong>
                  </div>
                  <div>
                    <span>sDIEM</span>
                    <strong>{formatToken(sdiemBalance)}</strong>
                  </div>
                  <div>
                    <span>csDIEM</span>
                    <strong>{formatToken(csBalance)}</strong>
                  </div>
                  <div>
                    <span>csDIEM vault</span>
                    <strong>{formatToken(csTotalAssets)}</strong>
                  </div>
                  <div>
                    <span>USDC rewards</span>
                    <strong>{formatUsd(pendingUsdc)}</strong>
                  </div>
                  <div>
                    <span>Pending harvest</span>
                    <strong>{formatUsd(pendingHarvest)}</strong>
                  </div>
                </div>

                <div className="pool-rewards-card">
                  <div>
                    <span>Claimable USDC</span>
                    <strong>{formatUsd(pendingUsdc)}</strong>
                  </div>
                  <button
                    className="pool-secondary-action"
                    disabled={isBusy || pendingUsdc <= 0n}
                    onClick={handleClaim}
                    type="button"
                  >
                    Claim
                  </button>
                </div>
              </>
            )}
          </aside>
        </section>

        <footer className="pool-links-footer">
          <a href="/docs">Docs</a>
          <a href="/about">About</a>
          <a href={GITHUB_URL} rel="noreferrer" target="_blank">GitHub</a>
          <a href={CONTRACTS_SECTION_URL}>Contracts (BaseScan)</a>
        </footer>
      </div>
      </div>
    </>
  );
}
