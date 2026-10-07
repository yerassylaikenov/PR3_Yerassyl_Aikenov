import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { keccak256, toBytes, toHex, stringToHex } from "viem";

const DEMO_DOC = new URL("../../demo-data/payment-order-0001.xml", import.meta.url);

enum Status {
  None = 0,
  Registered = 1,
  Executed = 2,
  Rejected = 3,
  Cancelled = 4,
}

describe("PaymentOrderRegistry (integration, viem + node:test)", async function () {
  const { viem } = await network.create();
  const publicClient = await viem.getPublicClient();
  const [adminWallet, operatorWallet, settlementWallet] = await viem.getWalletClients();
  const admin = adminWallet.account.address;
  const operator = operatorWallet.account.address;
  const settlement = settlementWallet.account.address;

  async function deployWithRoles() {
    const registry = await viem.deployContract("PaymentOrderRegistry", [admin]);
    const OPERATOR_ROLE = await registry.read.OPERATOR_ROLE();
    const SETTLEMENT_ROLE = await registry.read.SETTLEMENT_ROLE();
    await registry.write.grantRole([OPERATOR_ROLE, operator], { account: admin });
    await registry.write.grantRole([SETTLEMENT_ROLE, settlement], { account: admin });
    return { registry, OPERATOR_ROLE, SETTLEMENT_ROLE };
  }

  // OWASP SC01:2025, SC03:2025
  it("full flow: register (operator) -> markExecuted (settlement) with events", async function () {
    const { registry } = await deployWithRoles();
    const paymentId = keccak256(stringToHex("PAY-INTEGRATION-1"));
    const docHash = keccak256(stringToHex("doc-1"));
    const amount = 12_500_000_000n;

    await viem.assertions.emitWithArgs(
      registry.write.registerPayment([paymentId, docHash, amount], { account: operator }),
      registry,
      "PaymentRegistered",
      [paymentId, docHash, amount, operator],
    );

    await viem.assertions.emitWithArgs(
      registry.write.markExecuted([paymentId], { account: settlement }),
      registry,
      "PaymentStatusChanged",
      [paymentId, Status.Registered, Status.Executed, settlement, toHex(0, { size: 32 })],
    );

    const p = await registry.read.getPayment([paymentId]);
    assert.equal(p.status, Status.Executed);
    assert.equal(p.amount, amount);
    assert.equal(p.registeredBy.toLowerCase(), operator.toLowerCase());
    assert.equal(p.settledBy.toLowerCase(), settlement.toLowerCase());
    assert.equal(await registry.read.totalRegistered(), 1n);

    const events = await publicClient.getContractEvents({
      address: registry.address,
      abi: registry.abi,
      eventName: "PaymentStatusChanged",
      fromBlock: 0n,
      strict: true,
    });
    assert.equal(events.length, 1);
  });

  // OWASP SC01:2025 — four-eyes principle
  it("reverts with SelfSettlementForbidden when the initiator tries to settle", async function () {
    const { registry, OPERATOR_ROLE, SETTLEMENT_ROLE } = await deployWithRoles();
    // address with both roles (misconfiguration scenario)
    await registry.write.grantRole([OPERATOR_ROLE, settlement], { account: admin });
    const paymentId = keccak256(stringToHex("PAY-INTEGRATION-2"));
    await registry.write.registerPayment([paymentId, keccak256(stringToHex("doc-2")), 1n], {
      account: settlement,
    });
    assert.ok(await registry.read.hasRole([SETTLEMENT_ROLE, settlement]));

    await viem.assertions.revertWithCustomErrorWithArgs(
      registry.write.markExecuted([paymentId], { account: settlement }),
      registry,
      "SelfSettlementForbidden",
      [settlement],
    );
    const p = await registry.read.getPayment([paymentId]);
    assert.equal(p.status, Status.Registered);
  });

  // OWASP SC03:2025 — integrity of the off-chain document
  it("verifyDocument: true for demo-data/payment-order-0001.xml, false for tampered content", async function () {
    const { registry } = await deployWithRoles();
    const original = await readFile(DEMO_DOC);
    const docHash = keccak256(original);
    const tampered = Buffer.from(original.toString("utf8").replace("125000000.00", "925000000.00"), "utf8");
    const tamperedHash = keccak256(tampered);
    assert.notEqual(docHash, tamperedHash);

    const paymentId = keccak256(toBytes("PAY-INTEGRATION-3"));
    await registry.write.registerPayment([paymentId, docHash, 12_500_000_000n], { account: operator });

    assert.equal(await registry.read.verifyDocument([paymentId, docHash]), true);
    assert.equal(await registry.read.verifyDocument([paymentId, tamperedHash]), false);
  });
});
