# iOS TestFlight 測試版上架紀錄

目標：把「珠串」上架到 TestFlight，產生可讓其他 iOS 手機安裝的測試版本。

## 目前狀態

- App 名稱：`珠串`
- Bundle ID：`com.pinwai.zhuchuan`
- 版本：`0.1.0`
- Build：`2`
- Apple Team ID：`B8PCN3A826`
- Release archive：已可建立
- App Store/TestFlight IPA：目前被 Apple 簽章權限擋住

## 已完成的發佈準備

- Bundle ID 已從預設 `com.example.zhuchuanApp` 改成 `com.pinwai.zhuchuan`。
- iOS app icon 已換成珠串品牌圖，不再使用 Flutter 預設 placeholder。
- iOS launch image 已換成深色品牌圖，不再使用 Flutter 預設 placeholder。
- 已加入 `ios/ExportOptions-AppStore.plist`，之後可用於 App Store Connect/TestFlight 匯出。
- 已加入 `scripts/build_testflight.sh`，權限補齊後可用同一條流程建置與上傳。
- 已驗證可以建立 release archive：

```bash
scripts/build_testflight.sh
```

## 目前阻擋點

本機可以 archive，但無法產生可上傳 TestFlight 的 App Store IPA。實際錯誤：

```text
No signing certificate "iOS Distribution" found
Team does not have permission to create "iOS App Store" provisioning profiles
No profiles for 'com.pinwai.zhuchuan' were found
```

前兩項是關鍵：目前 Apple 帳號/team 沒有 App Store Distribution 簽章與建立 App Store provisioning profile 的權限。這通常代表需要：

- 加入 Apple Developer Program，或
- 使用已有 Apple Developer Program 的 team，並取得 App Manager / Admin / Account Holder 權限，或
- 讓有權限的人在 App Store Connect 建立 App 與簽章後提供 API key / 登入環境。

> iOS 不能像 Android APK 那樣用公開網址直接安裝任意 `.ipa`。要讓不特定 iPhone 安裝測試版，正規方式是 TestFlight 公開連結。

## 權限補齊後的最短流程

1. 在 Apple Developer / App Store Connect 確認 bundle id：

```text
com.pinwai.zhuchuan
```

2. 在 App Store Connect 建立 App：

```text
Name: 珠串
Bundle ID: com.pinwai.zhuchuan
SKU: zhuchuan-ios
Primary Language: Traditional Chinese
```

3. 在 Xcode 登入有權限的 Apple ID，或設定 App Store Connect API key。

4. 重新產生 IPA：

```bash
flutter clean
flutter pub get
scripts/build_testflight.sh
```

5. 若要用 App Store Connect API key 上傳，先放好 `.p8` key：

```text
~/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8
```

再執行：

```bash
export ASC_API_KEY_ID=YOUR_KEY_ID
export ASC_API_ISSUER_ID=YOUR_ISSUER_ID
scripts/build_testflight.sh
```

腳本會在成功產生 IPA 後自動呼叫：

```bash
xcrun altool --upload-app \
  --type ios \
  --file build/ios/ipa/zhuchuan_app.ipa \
  --apiKey YOUR_API_KEY_ID \
  --apiIssuer YOUR_ISSUER_ID
```

也可以用 Xcode Organizer 開啟 archive 後按 Distribute App：

```bash
open build/ios/archive/Runner.xcarchive
```

6. App Store Connect 處理完成後，到 TestFlight：

- 填寫出口合規資訊
- 加入內部測試員，或建立外部測試群組
- 若要「公開連結」，在外部測試群組開啟 Public Link

## 目前產物

- Release archive：

```text
build/ios/archive/Runner.xcarchive
```

這個 archive 已產生，但目前不能直接給其他 iPhone 安裝；仍需完成 Apple Distribution 簽章並上傳 TestFlight。
