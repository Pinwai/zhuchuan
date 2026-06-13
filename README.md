# 珠串 App MVP

Flutter 雙平台手鍊設計工具 MVP。第一版支援本機素材、手圍估算、2D 俯視串珠、自由拖放、本機保存與圖片匯出。

## 目前內容

- `lib/`：Flutter App 原始碼。
- `assets/catalog.json`：內建素材與推薦套裝。
- `test/`：手圍估算與資料模型測試。

## 在有 Flutter SDK 的機器上執行

```bash
flutter create --platforms=ios,android .
flutter pub get
flutter test
flutter run
```

如果要先用模擬器驗證，請先打開 iOS Simulator 或 Android Emulator。

## 第一版範圍

- 已包含：分類、珠子滑軌、尺寸切換、手圍估算、2D 手鍊畫布、拖放新增/替換、序列拖曳排序、本機儲存、PNG 匯出。
- 未包含：登入、雲端同步、遠端素材庫、購物車、付款、庫存、AR 試戴。
