use strict;

package XML::Handler::Trees;
use vars qw/$VERSION/;
$VERSION = '0.01';

package XML::Handler::Tree;

sub new {
  my $class = ref($_[0]) || $_[0];
  bless {},$class;
}

sub start_document {
  my $self=shift;
  $self->{Lists}=[];
  $self->{Curlist}=$self->{Tree}=[];
}

sub start_element {
  my ($self,$element)=@_;
  my $newlist;
  if (ref $element->{Attributes} eq 'HASH') {
    $newlist=[{map {$_=>$element->{Attributes}{$_}} keys %{$element->{Attributes}}}];
  }
  else {
    $newlist=[{map {$_=>$element->{Attributes}{$_}{Value}} keys %{$element->{Attributes}}}];
  }
  push @{ $self->{Lists} }, $self->{Curlist};
  push @{ $self->{Curlist} }, $element->{Name} => $newlist;
  $self->{Curlist} = $newlist;
}

sub end_element {
  my ($self,$element)=@_;
  $self->{Curlist}=pop @{$self->{Lists}};
}

sub characters {
  my ($self,$text)=@_;
  my $clist = $self->{Curlist};
  my $pos = $#$clist;
  if ($pos>0 and $clist->[$pos-1] eq '0') {
    $clist->[$pos].=$text->{Data};
  }
  else {
    push @$clist,0=>$text->{Data};
  }
}

sub comment {}

sub processing_instruction {}

sub end_document {
  my $self=shift;
  delete $self->{Curlist};
  delete $self->{Lists};
  $self->{Tree};
}

package XML::Handler::EasyTree;

use vars qw($Noempty $Latin);

sub new {
  my $class=shift;
  $class=ref($class) || $class;
  my $self={Noempty=>0,Latin=>0,@_};
  bless $self,$class;
}

sub start_document {
  my $self = shift;
  $self->{Lists} = [];
  $self->{Curlist} = $self->{Tree} = [];
}

sub start_element {
  my ($self,$element)=@_;
  $self->checkempty();
  my $newlist=[];
  my $newnode={type=>'e',attrib=>{},name=>$self->nsname($element),content=>$newlist};
  if (ref $element->{Attributes} eq 'HASH') {
    while (my ($name,$val)=each %{$element->{Attributes}}) {
      $newnode->{attrib}{$self->nsname($name)}=$self->encode($val);
    }
  }
  else {
    foreach my $att (keys %{$element->{Attributes}}) {
      $newnode->{attrib}{$self->nsname($element->{Attributes}{$att})}=$self->encode($element->{Attributes}{$att}{Value});
    }
  }
  push @{ $self->{Lists} }, $self->{Curlist};
  push @{ $self->{Curlist} }, $newnode;
  $self->{Curlist} = $newlist;
}

sub end_element {
  my $self=shift;
  $self->checkempty();
  $self->{Curlist}=pop @{$self->{Lists}};
}

sub characters {
  my ($self,$text)=@_;
  my $clist=$self->{Curlist};
  if (!@$clist || $clist->[-1]{type} ne 't') {
    push @$clist,{type=>'t',content=>''};
  }
  $clist->[-1]{content}.=$self->encode($text->{Data});
}

sub processing_instruction {
  my ($self,$pi)=@_;
  $self->checkempty();
  my $clist=$self->{Curlist};
  push @$clist,{type=>'p',target=>$self->encode($pi->{Target}),content=>$self->encode($pi->{Data})};
}

sub comment {}

sub end_document {
  my $self = shift;
  $self->checkempty();
  delete $self->{Curlist};
  delete $self->{Lists};
  $self->{Tree};
}

sub nsname {
  my ($self,$name)=@_;
  if (ref $name) {
    if (defined $name->{NamespaceURI}) {
      $name="{$name->{NamespaceURI}}$name->{LocalName}";
    }
    else {
      $name=$name->{Name};
    }
  }
  return $self->encode($name);    
}

sub encode {
  my ($self,$text)=@_;
  if ($self->{Latin}) {
    $text=~s{([\xc0-\xc3])(.)}{
      my $hi = ord($1);
      my $lo = ord($2);
      chr((($hi & 0x03) <<6) | ($lo & 0x3F))
     }ge;
  }
  $text;
}

sub checkempty() {
  my $self=shift;
  if ($self->{Noempty}) {
    my $clist=$self->{Curlist};
    if (@$clist && $clist->[-1]{type} eq 't' && $clist->[-1]{content}=~/^\s+$/) {
      pop @$clist;
    }
  }
}

package XML::Handler::TreeBuilder;

use vars qw(@ISA);
@ISA=qw(XML::Element);

sub new {
  require XML::Element; 
  my $class = ref($_[0]) || $_[0];
  my $self = XML::Element->new('NIL');
  $self->{'_element_class'} = 'XML::Element';
  $self->{'_store_comments'}     = 0;
  $self->{'_store_pis'}          = 0;
  $self->{'_store_declarations'} = 0;
  $self->{_stack}=[];
  bless $self, $class;
}
  
sub start_document {}

sub start_element {
  my ($self,$element)=@_;
  my @attlist;
  if (ref $element->{Attributes} eq 'HASH') {
    @attlist=map {$_=>$element->{Attributes}{$_}} keys %{$element->{Attributes}};
  } 
  else {
    @attlist=map {$_=>$element->{Attributes}{$_}{Value}} keys %{$element->{Attributes}};
  }
  if(@{$self->{_stack}}) {
    push @{$self->{_stack}}, $self->{'_element_class'}->new($element->{Name},@attlist);
    $self->{_stack}[-2]->push_content( $self->{_stack}[-1] );
  }
  else {
    $self->tag($element->{Name});
    while(@attlist) {
      $self->attr(splice(@attlist,0,2));
    }
    push @{$self->{_stack}}, $self;
  }
}

sub end_element {
  my $self=shift;
  pop @{$self->{_stack}};
  return
}

sub characters {
  my ($self,$text)=@_;
  $self->{_stack}[-1]->push_content($text->{Data});
}
    
sub comment {
  my ($self,$comment)=@_;
  return unless $self->{'_store_comments'};
  (@{$self->{_stack}} ? $self->{_stack}[-1] : $self)->push_content(
      $self->{'_element_class'}->new('~comment', 'text' => $comment->{Data})
    );
  return;
}

sub processing_instruction {
  my ($self,$pi)=@_;
  return unless $self->{'_store_pis'};
  (@{$self->{_stack}} ? $self->{_stack}[-1] : $self)->push_content(
      $self->{'_element_class'}->new('~pi', 'text' => "$pi->{Target} $pi->{Data}")
    );
  return;
}

sub end_document {    
  my $self=shift;
  return $self;
}

sub _elem # universal accessor...
{
  my($self, $elem, $val) = @_;
  my $old = $self->{$elem};
  $self->{$elem} = $val if defined $val;
  return $old;
}

sub store_comments { shift->_elem('_store_comments', @_); }
sub store_declarations { shift->_elem('_store_declarations', @_); }
sub store_pis      { shift->_elem('_store_pis', @_); }

1;
__END__

=head1 NAME

XML::Handler::Trees - PerlSAX handlers for building tree structures

=head1 SYNOPSIS

  use XML::Handler::Trees;
  use XML::Parser::PerlSAX;

  my $p=XML::Parser::PerlSAX->new();
  my $h=XML::Handler::Tree->new();
  my $tree=$p->parse(Handler=>$h,Source=>{SystemId=>'file.xml'});

  my $p=XML::Parser::PerlSAX->new();
  my $h=XML::Handler::EasyTree->new(Noempty=>1);
  my $easytree=$p->parse(Handler=>$h,Source=>{SystemId=>'file.xml'});

  my $p=XML::Parser::PerlSAX->new();
  my $h=XML::Handler::TreeBuilder->new();
  $h->store_pis(1);
  my $tree=$p->parse(Handler=>$h,Source=>{SystemId=>'file.xml'});

=head1 DESCRIPTION

XML::Handler::Trees provides three PerlSAX handler classes for building
tree structures.  XML::Handler::Tree builds the same type of tree as the
"Tree" style in XML::Parser.  XML::Handler::EasyTree builds the same
type of tree as the "EasyTree" style added to XML::Parser by
XML::Parser::EasyTree.  XML::Handler::TreeBuilder builds the same type
of tree as Sean M. Burke's XML::TreeBuilder.  These classes make it
possible to construct these tree structures from sources other than
XML::Parser.

All three handlers can be driven by either PerlSAX 1 or PerlSAX 2
drivers.  In all cases, the end_document() method returns a reference to
the constructed tree, which normally becomes the return value of the
PerlSAX driver.

=head1 CLASS XML::Handler::Tree

This handler builds the same type of tree structure as the "Tree" style
in XML::Parser.  Some modules such as Dan Brian's XML::SimpleObject work
with this type of tree.  See the documentation for XML::Parser for details.  

=head2 METHODS

=over 4

=item $handler = XML::Handler::Tree->new()

Creates a handler object.

=back

=head1 CLASS XML::Handler::EasyTree

This handler builds a lightweight tree structure representing the XML 
document.  This structure is, at least in this author's opinion, easier to 
work with than the "standard" style of tree.  It is the same type of
structure as built by XML::Parser when using XML::Parser::EasyTree, or
by the get_simple_tree method in XML::Records.

The tree is returned as a reference to an array of tree nodes, each of
which is a hash reference. All nodes have a 'type' key whose value is
the type of the node: 'e' for element nodes, 't' for text nodes, and 'p'
for processing instruction nodes. All nodes also have a 'content' key
whose value is a reference to an array holding the element's child nodes
for element nodes, the string value for text nodes, and the data value
for processing instruction nodes. Element nodes also have an 'attrib'
key whose value is a reference to a hash of attribute names and values.
Processing instructions also have a 'target' key whose value is the PI's
target. 

EasyTree nodes are ordinary Perl hashes and are not objects.  Contiguous 
runs of text are always returned in a single node.

The reason the parser returns an array reference rather than the root 
element's node is that an XML document can legally contain processing 
instructions outside the root element (the xml-stylesheet PI is commonly 
used this way).

If namespace information is available (only possible with PerlSAX 2),
element and attribute names will be prefixed with their (possibly empty)
namespace URI enclosed in curly brackets, and namespace prefixes will be
stripped from names.

=head2 METHODS

=over 4

=item $handler = XML::Handler::EasyTree->new([options])

Creates a handler object.  Options can be provided hash-style:

=over 4

=item Noempty

If this is set to a true value, text nodes consisting entirely of
whitespace will not be stored in the tree.  The default is false.

=item Latin

If this is set to a true value, characters with Unicode values in the
Latin-1 range (160-255) will be stored in the tree as Latin-1 rather
than UTF-8.  The default is false.

=back

=back

=head1 CLASS XML::Handler::TreeBuilder

This handler builds XML document trees constructed of
XML::Element objects (XML::Element is a subclass of HTML::Element
adapted for XML).  To use it, XML::TreeBuilder and its prerequisite
HTML::Tree need to be installed.  See the documentation for those
modules for information on how to work with these tree structures.

=head2 METHODS

=over 4

=item $handler = XML::Handler::TreeBuilder->new()

Creates a handler which builds a tree rooted in an XML::Element.

=item $root->store_comments(value)

This determines whether comments will be stored in the tree (not all SAX
drivers generate comment events).  Currently, this is off by default.

=item $root->store_declarations(value)

This determines whether markup declarations will be stored in the tree.
Currently, this is off by default.  The present implementation does not
store markup declarations in any case; this method is provided for future use.

=item $root->store_pis(value)

This determines whether processing instructions will be stored in the tree.
Currently, this is off (false) by default.

=back

=head1 AUTHOR

Eric Bohlman (ebohlman@omsdev.com)

Copyright (c) 2001 Eric Bohlman. All rights reserved. This program
is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 SEE ALSO

 L<perl>
 L<XML::Parser>
 L<XML::SimpleObject>
 L<XML::Parser::EasyTree>
 L<XML::TreeBuilder>
 L<XML::Element>
 L<HTML::Element>
 L<PerlSAX>

=cut
