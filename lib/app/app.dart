import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/patient/blocs/patient_bloc.dart';
import '../features/gesture/gesture_nav_wrapper.dart';
import '../features/voice/bhashini_service.dart';
import 'routes.dart';
import 'theme.dart';

/// Root widget of the SAHA application.
///
/// Provides global [BlocProvider]s and configures the MaterialApp
/// with routing and theming.
class SahaApp extends StatelessWidget {
  const SahaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PatientBloc>(
          create: (_) => PatientBloc()..add(const LoadPatients()),
        ),
      ],
      child: StreamBuilder<Locale>(
        stream: BhashiniService.instance.localeStream,
        initialData: BhashiniService.instance.currentLocale,
        builder: (context, snapshot) {
          return MaterialApp.router(
            title: 'SAHA',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.light,
            routerConfig: appRouter,
            locale: snapshot.data ?? const Locale('en'),
            builder: (context, child) {
              return GestureNavWrapper(
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
