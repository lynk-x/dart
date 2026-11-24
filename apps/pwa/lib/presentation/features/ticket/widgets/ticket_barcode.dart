import 'package:material_ui/material_ui.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/ticket/cubit/ticket_totp_cubit.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

/// Renders the barcode/QR section with dynamic TOTP anti-screenshot protection.
class TicketBarcodeSection extends StatelessWidget {
  final TicketModel ticket;
  final double height;
  final double? width;
  final bool isWidescreen;

  const TicketBarcodeSection({
    super.key,
    required this.ticket,
    this.height = 60,
    this.width,
    this.isWidescreen = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TicketTotpCubit, TicketTotpState>(
      builder: (context, totpState) {
        final barcodeData = totpState.barcodePayload.isNotEmpty
            ? totpState.barcodePayload
            : ticket.displayCode;

        if (isWidescreen) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            color: Colors.white,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RepaintBoundary(
                  child: BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: barcodeData,
                    drawText: false,
                    color: Colors.black,
                    height: height,
                    width: width ?? double.infinity,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '#${ticket.displayCode}',
                  style: AppTypography.inter(
                    fontSize: 15,
                    color: Colors.black54,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          child: Column(
            children: [
              RepaintBoundary(
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: barcodeData,
                  drawText: false,
                  color: Colors.black,
                  height: height,
                  width: width ?? double.infinity,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '#${ticket.displayCode}',
                style: AppTypography.inter(
                  fontSize: 14,
                  color: Colors.black45,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }
}
