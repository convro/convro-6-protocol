//
//  C6PWireAAD.swift
//  C6P-Protocol
//
//  Deterministyczne AAD dla warstwy WIRE (envelope header binding).
//
//  Cel:
//  - Serwer może routować ciphertext, ale NIE może zmienić routingu (from/to/session/clientMessageId)
//    bez wykrycia na kliencie (AEAD tag fail).
//
//  AAD jest stałej długości (brak zmiennych stringów):
//  - clientMessageId jest hashowane do 16 bajtów (truncated SHA256) – stabilne i szybkie.
//

import Foundation
import CryptoKit

enum C6PWireAAD {

    /// Wersja formatu WIRE-AAD (nie mylić z C6P_VERSION).
    /// Zmienisz tylko, jeśli zmieniasz layout AAD.
    static let wireAADVersion: UInt8 = 1

    /// Buduje AAD bindujące routing envelope'u do kryptografii.
    ///
    /// Layout (big-endian / stała kolejność):
    ///  [ 0 ]      wireAADVersion (0x01)
    ///  [ 1 ]      c6pVersion (C6P_VERSION)
    ///  [2..5]     sessionId (4 bytes)
    ///  [6..13]    fromDeviceId (8 bytes)
    ///  [14..21]   toDeviceId (8 bytes)
    ///  [22..37]   clientMessageIdHash16 (16 bytes) = SHA256(utf8(clientMessageId)).prefix(16)
    ///
    /// Uwaga: serverTimestamp/serverMessageId/deliveryState NIE wchodzą do AAD (mogą się zmieniać).
    static func envelopeAAD(
        c6pVersion: UInt8 = C6P_VERSION,
        sessionId: C6PSessionId,
        fromDeviceId: C6PDeviceId,
        toDeviceId: C6PDeviceId,
        clientMessageId: String
    ) -> Data {

        var data = Data()
        data.reserveCapacity(38)

        data.append(wireAADVersion)
        data.append(c6pVersion)

        data.append(sessionId.data)
        data.append(fromDeviceId.data)
        data.append(toDeviceId.data)

        let msgIdHash16 = hashClientMessageId16(clientMessageId)
        data.append(msgIdHash16)

        return data
    }

    /// 16-bajtowy “fingerprint” clientMessageId (stała długość AAD).
    private static func hashClientMessageId16(_ clientMessageId: String) -> Data {
        let utf8 = Data(clientMessageId.utf8)
        let digest = SHA256.hash(data: utf8)
        return Data(digest).prefix(16)
    }
}
