import 'package:flutter/material.dart';

import '../../../data/models/owner.dart';

/// One row of the owner list: name and, if known, a contact.
class OwnerTile extends StatelessWidget {
  /// Creates the row for [owner], calling [onTap] when tapped.
  const OwnerTile({super.key, required this.owner, required this.onTap});

  /// The owner shown.
  final Owner owner;

  /// Opens the owner detail.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final contact = owner.phone ?? owner.email;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(owner.fullName),
      subtitle: contact == null ? null : Text(contact),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
