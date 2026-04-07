# Lynk-X Core

Shared core library for the Lynk-X ecosystem, providing a unified theme system for both the Flutter mobile app and the Next.js web application.

## Theme System

The theme system uses a **Single Source of Truth** pattern. All design tokens are defined in a JSON file and then generated into platform-specific code.

### 1. Source of Truth

Tokens are defined in:
`theme/tokens.json`

This file contains:

- **Colors**: Brand, Utility, and Semantic (Interface) colors.
- **Typography**: Font families and predefined text styles (H1, H2, Body, etc.).
- **Spacing**: A standardized spacing scale for margins and padding.
- **Radius**: Border radius tokens for consistent corner rounding.
- **Shadows**: Standardized elevation and shadow effects.
- **Icons**: Predefined icon sizes.

### 2. Code Generation

To update the theme code after modifying `tokens.json`, run the following command from the `core` directory:

```bash
node scripts/generate_theme.js
```

This script generates:

- **Flutter**: `lib/src/theme/app_colors.dart`, `app_typography.dart`, `app_dimensions.dart`, `app_shadows.dart`.
- **Web**: `../web/src/theme/tokens.ts`.

### 3. Usage

#### Flutter (Mobile)

Add the core package to your `pubspec.yaml`:

```yaml
dependencies:
  core:
    path: ../core
```

Use the generated classes:

```dart
import 'package:core/core.dart';

Container(
  padding: EdgeInsets.all(AppDimensions.spacingMd),
  decoration: BoxDecoration(
    color: AppColors.primary,
    borderRadius: AppDimensions.borderRadiusMd,
    boxShadow: AppShadows.md,
  ),
  child: Text('Hello World', style: AppTypography.h1),
)
```

#### Next.js (Web)

Import the tokens in your TypeScript project:

```typescript
import { tokens } from '@/theme/tokens';

const primaryColor = tokens.colors.brand.primary;
const spacing = tokens.spacing.md;
```

### 4. Shared Assets

Images are stored in `assets/images/` and registered in `pubspec.yaml`. Flutter apps can access them using:
`packages/core/assets/images/filename.png`

## Setup & Maintenance

1. **Install Dependencies**:
   Run `flutter pub get` in this directory to fetch Flutter and font dependencies.
2. **Updating Tokens**:
   Edit `theme/tokens.json` and run the generator script.
3. **Adding New Types**:
   Update `scripts/generate_theme.js` to handle new token categories.
