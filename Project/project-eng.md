# Travel Attraction Finder - Project Documentation (Stage 3.8.1)

## English Version

### 1. Project Overview
This project is an iOS travel attraction finder application based on MVVM architecture, featuring intelligent map search, Google Places API integration, Wikipedia API integration, and multi-language support. The application uses modern SwiftUI interface to provide a smooth user experience.

### 2. Technical Architecture
- **Development Environment**: Xcode 16.1 + SwiftUI
- **Programming Language**: Swift 5.9
- **Architecture Pattern**: MVVM (Model-View-ViewModel)
- **Map Services**: MapKit + Google Places API
- **Data Sources**: Wikipedia API (multi-language support)
- **UI Framework**: SwiftUI
- **Minimum Support**: iOS 18.5

### 3. Core Features (Stage 3.8.1)

#### 🗺️ **Intelligent Map Search System**
- **Real-time Location**: Precise user location using CoreLocation
- **Smart Attraction Search**: Automatic search within 20km radius
- **Google Places API Integration**: High-quality attraction data source
- **Map Visualization**: MapKit displays attraction locations and details
- **Search Progress Display**: Real-time progress and found attraction count

#### 📚 **Wikipedia API Integration**
- **Multi-language Support**: Traditional Chinese, Simplified Chinese, English
- **Smart Content Matching**: Auto-match Wikipedia entries by attraction names
- **Rich Content Display**: Detailed descriptions, historical background
- **Image Integration**: Automatic Wikipedia image resource retrieval
- **Offline Caching**: Optimized loading speed, reduced duplicate requests

#### 🎯 **Three-Dimensional Search Matching System**
- **Semantic Dimension**: Query and database location name tokenization, common prefix/suffix removal, synonym/translation/pinyin/abbreviation matching
- **Geographic Dimension**: Coordinate distance calculation, <1km considered same location
- **Attribute Dimension**: Attraction type matching (churches, beaches, stations, museums, etc.)
- **Comprehensive Scoring**: Three-dimensional score ranking, >0.7 passes matching
- **Global Support**: Not limited to Hong Kong, supports worldwide locations and multi-language

#### 🏛️ **Attraction Detailed Information**
- **Basic Information**: Name, address, coordinates, rating
- **Wikipedia Integration**: Detailed descriptions, historical background, related images
- **Geographic Location**: Precise coordinates and map display
- **User Reviews**: Ratings and reviews from Google Places
- **Related Links**: Official websites, social media, etc.

### 4. System Architecture (MVVM)

#### View Layer (User Interface)
- **TravelMapView**: Main map interface displaying attraction locations
- **AttractionDetailView**: Attraction detailed information page
- **ContentView**: Main application container

#### ViewModel Layer (Business Logic)
- **LocationViewModel**: Location service management
- **AttractionsListViewModel**: Attraction list management
- **AttractionDetailViewModel**: Attraction detail management
- **AttractionsManagementViewModel**: Attraction search and management

#### Model Layer (Data Services)
- **LocationService**: CoreLocation location service
- **NearbyAttractionsService**: Google Places API integration
- **WikipediaCache**: Wikipedia data caching
- **CompareModel**: Three-dimensional search matching logic
- **TemplateMemoryModel**: Data template management

### 5. Technical Features

#### 🚀 **Performance Optimization**
- **Smart Caching**: Wikipedia data local caching, reduced API requests
- **Asynchronous Processing**: All network requests use async/await pattern
- **Memory Management**: Optimized large data processing, prevent memory leaks
- **Error Handling**: Comprehensive error handling with user-friendly error messages

#### 🌐 **Multi-language Support**
- **Wikipedia Multi-language**: Support for zh-tw, zh-cn, en, and more
- **Smart Language Selection**: Auto-select appropriate language based on attraction location
- **Content Localization**: Interface text supports multi-language switching

#### 🔍 **Intelligent Search**
- **Fuzzy Matching**: Support partial keyword search
- **Synonym Recognition**: Recognize different naming conventions for attractions
- **Geographic Filtering**: Auto-filter relevant attractions by distance
- **Relevance Sorting**: Auto-sort search results by matching score

### 6. Development Environment

#### 📱 **Test Devices**
- **Development Environment**: Xcode 16.1, macOS Sequoia
- **Test Device**: iPhone 13 "Monster" (Device ID: 00008110-000C35D63CA2801E)
- **Deployment Method**: Direct deployment with Apple Developer certificate
- **Test Location**: Hong Kong Tseung Kwan O Choi Ming Court

#### 🔧 **Development Tools**
- **IDE**: Xcode 16.1
- **Version Control**: Git
- **Project Management**: Swift Package Manager
- **Debugging Tools**: Xcode Instruments
- **Documentation Tools**: Markdown

### 7. Project Structure

```
travel-diary/
├── App/
│   ├── ContentView.swift
│   └── travel_diaryApp.swift
├── Features/
│   ├── AttractionDetail/
│   │   ├── Models/
│   │   │   ├── AttractionCache.swift
│   │   │   ├── CompareModel.swift
│   │   │   └── TemplateMemoryModel.swift
│   │   ├── ViewModels/
│   │   │   ├── AttractionDetailViewModel.swift
│   │   │   ├── AttractionsListViewModel.swift
│   │   │   └── AttractionsManagementViewModel.swift
│   │   └── Views/
│   │       └── AttractionDetailView.swift
│   └── Map/
│       ├── ViewModels/
│       │   └── LocationViewModel.swift
│       └── Views/
│           └── TravelMapView.swift
├── Models/
│   ├── NearbyAttractionsModel.swift
│   └── WikipediaCache.swift
├── Services/
│   ├── LocationService.swift
│   └── NearbyAttractionsService.swift
└── Resources/
    └── Assets.xcassets/
```

### 8. Deployment Information

#### 📦 **Application Information**
- **Bundle ID**: `com.wilsonho.travelDiary`
- **Display Name**: "旅遊景點搜尋器" (Travel Attraction Finder)
- **Version**: Stage 3.8.1
- **Minimum Support**: iOS 18.5
- **Architecture**: arm64

#### 🔐 **Signing Information**
- **Developer Certificate**: Apple Development: wilson_23@hotmail.com (WP36TJ78N6)
- **Provisioning Profile**: iOS Team Provisioning Profile
- **Deployment Method**: Direct installation to test device

### 9. User Guide

#### 🚀 **Launch Application**
1. Open "Travel Attraction Finder" application
2. Allow location permission access
3. Wait for automatic location completion
4. System will automatically search attractions within 20km

#### 🗺️ **Using Map Features**
1. Map displays your current location
2. Red markers show found attraction locations
3. Tap markers to view basic attraction information
4. Use gestures to zoom and pan the map

#### 📖 **View Attraction Details**
1. Tap attraction markers on the map
2. View basic attraction information (name, address, rating)
3. Tap "View Details" button
4. Browse Wikipedia detailed descriptions and images

### 10. Technical Documentation

#### 🔧 **API Integration**
- **Google Places API**: Basic attraction information retrieval
- **Wikipedia API**: Detailed content and image retrieval
- **CoreLocation**: Location positioning service
- **MapKit**: Map display and interaction

#### 📊 **Data Flow**
1. User location retrieval → LocationService
2. Attraction search → Google Places API
3. Detailed information retrieval → Wikipedia API
4. Three-dimensional matching → CompareModel
5. Result display → SwiftUI Views

### 11. Version History

#### 🏷️ **Stage 3.8.1 (Current Version)**
- ✅ Complete travel attraction finder functionality
- ✅ Google Places API integration
- ✅ Wikipedia API multi-language support
- ✅ Three-dimensional search matching system
- ✅ Modern SwiftUI interface
- ✅ Comprehensive error handling
- ✅ Successfully deployed to iPhone test device

#### 🔄 **Previous Versions**
- **Stage 3.7.3**: Stable restore point with complete Google three-dimensional search system
- **Stage 3.6.x**: MVVM architecture refactoring
- **Stage 3.5.x**: Basic functionality implementation
- **Stage 2.x**: Prototype development

### 12. Future Development

#### 🎯 **Planned Features**
- **Offline Maps**: Support offline map browsing
- **Personalized Recommendations**: Recommend attractions based on user preferences
- **Social Features**: User comments and sharing
- **Multi-platform Support**: iPad and Mac version development

#### 🚀 **Technical Optimization**
- **Performance Enhancement**: Further optimize loading speed
- **UI/UX Improvements**: More intuitive user interface
- **Feature Expansion**: Support more attraction types
- **Internationalization**: More language support

---

## 📱 Project Status Summary

### ✅ **Current Status (Stage 3.8.1)**
- **Feature Completeness**: 100% - All core features working properly
- **Stability**: Excellent - No known crash issues
- **Performance**: Good - Responsive and smooth loading
- **User Experience**: Excellent - Intuitive and user-friendly interface
- **Deployment Status**: Success - Deployed to test device and running normally

### 🎯 **Technical Achievements**
- Complete MVVM architecture implementation
- Successful integration of multiple external APIs
- Implementation of complex three-dimensional search matching algorithm
- Excellent error handling and user feedback
- Modern SwiftUI interface design

### 📈 **Project Value**
- Practical travel tool application
- Strong technical architecture scalability
- High code quality and maintainability
- Excellent user experience
- Commercial potential

---

*Last Updated: January 15, 2025*
*Version: Stage 3.8.1*
*Status: Stable version, recommended for use*
