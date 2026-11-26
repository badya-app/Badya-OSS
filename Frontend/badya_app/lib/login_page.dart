import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'widgets/login_form.dart';
import 'widgets/login_header.dart';
import 'widgets/signup_navigation.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgImage = isDark
        ? 'assets/images/logindark.svg'
        : 'assets/images/login_background.svg';

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: SvgPicture.asset(
              bgImage,
              fit: BoxFit.cover,
            ).animate().fadeIn(duration: 800.ms),
          ),
          Container(
            color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.15),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: const IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Spacer(),
                          LoginHeader(),
                          SizedBox(height: 32),
                          LoginForm(),
                          Spacer(),
                          SizedBox(height: 24),
                          SignUpNavigation(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
