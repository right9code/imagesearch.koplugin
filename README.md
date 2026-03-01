# Image Search & AI Generation Plugin for KOReader
| Plugin Menu | Image Search |
|:-------------------------:|:-------------------------:|
| ![](imagesearch1.png) | ![](imagesearch2.png) |

A powerful plugin for KOReader that allows you to search for images on the web or generate them using state-of-the-art AI, all directly from your e-reader.

## ✨ Features
- **🌍 Image Search**: Search Wikipedia (Wikimedia Commons), Openverse, and DuckDuckGo.
- **🤖 AI Generation**: Generate custom images from prompts using **Google Gemini** or **Pollinations.ai**.
- **🖼️ Smart Viewer**: View results in a customizable grid (2x2, 3x3, etc.).
- **💾 Save & Download**: Save any image directly to your device's storage.
- **🔍 Selection Search**: Select any text in a book to instantly search or generate an image for it.
- **🚀 Performance**: Optimized for E-Ink with local caching and page-based loading.

## 🛠️ Setup & Requirements

### Installation
1. Copy the `imagesearch.koplugin` folder to your KOReader `plugins/` directory.
2. Restart KOReader.

### AI Provider Configuration
The plugin supports two AI providers:

#### 1. Pollinations.ai (Default)
- **Status**: Requires API key now
- **Setup**: [Register on the website and generate api-keys](https://pollinations.ai/)

#### 2. Google Gemini (Nano Banana)
- **Status**: High-quality, requires API Key.
- **Setup**:
    1. Get a free API key from [Google AI Studio](https://aistudio.google.com/).
    2. In the plugin menu, go to **Settings > Set Gemini API Key**.
    3. (Optional) You can also hardcode your key in `gemini_client.lua` for ease of use across devices.

## 📱 Usage Guide

### Main Menu
Open the plugin from the KOReader top menu or "Search" menu:
1. **Search Images...**: Type a keyword to find photos/illustrations.
2. **Generate Image (AI)...**: Type a prompt (e.g., "A futuristic library in space") to create something new.
3. **Settings**: Adjust the search source, grid layout, download folder, and AI credentials.

### Selection Menu
Highlight any text in a book. A new option **"Image Search"** or **"Generate Image (AI)"** will appear in the context menu to instantly visualize what you are reading.

### Image Viewer
Tap any thumbnail to see it full-screen. 
- Use the **"Save"** button to download it to your chosen directory.
- Use KOReader's native zoom and rotation tools to inspect details.

## ⚙️ Configuration
| Setting | Description |
| :--- | :--- |
| **Search Source** | Choose between DuckDuckGo, Wikipedia, or Openverse. |
| **AI Provider** | Switch between Pollinations.ai (Requires API Key now) or Gemini (Paid/API Key required). |
| **Download Directory** | Set where saved images are stored (Default: Device Root, e.g., `/mnt/onboard`). |
| **Grid Rows/Cols** | Customize how many images show per page (e.g., 2 for large views, 3 for more variety). |

---
**Author**: right9code  
**Version**: 1.1  
**License**: [Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/)
